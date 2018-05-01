{-# LANGUAGE GADTs #-}
module Semantic.Graph where

import           Analysis.Abstract.BadAddresses
import           Analysis.Abstract.BadModuleResolutions
import           Analysis.Abstract.BadSyntax
import           Analysis.Abstract.BadValues
import           Analysis.Abstract.BadVariables
import           Analysis.Abstract.Erroring
import           Analysis.Abstract.Evaluating
import           Analysis.Abstract.ImportGraph
import           Analysis.Abstract.Graph (Graph, renderGraph)
import qualified Control.Exception as Exc
import           Data.Abstract.Address
import qualified Data.Abstract.Evaluatable as Analysis
import           Data.Abstract.FreeVariables
import           Data.Abstract.Located
import           Data.Abstract.Module
import           Data.Abstract.Package as Package
import           Data.Abstract.Value (Value)
import           Data.File
import           Data.Output
import qualified Data.Syntax as Syntax
import           Data.Term
import           Parsing.Parser
import           Prologue hiding (MonadError (..))
import           Rendering.Renderer
import           Semantic.IO (Files)
import           Semantic.Task

graph :: Members '[Distribute WrappedTask, Files, Task, Exc SomeException, Telemetry] effs
      => GraphRenderer output
      -> Project
      -> Eff effs ByteString
graph renderer project
  | SomeAnalysisParser parser prelude <- someAnalysisParser
    (Proxy :: Proxy '[ Analysis.Evaluatable, Analysis.Declarations1, FreeVariables1, Functor, Eq1, Ord1, Show1 ]) (projectLanguage project) = do
    parsePackage parser prelude project >>= graphImports >>= case renderer of
      JSONGraphRenderer -> pure . toOutput
      DOTGraphRenderer  -> pure . renderGraph

-- | Parse a list of files into a 'Package'.
parsePackage :: Members '[Distribute WrappedTask, Files, Task] effs
             => Parser term       -- ^ A parser.
             -> Maybe File        -- ^ Prelude (optional).
             -> Project           -- ^ Project to parse into a package.
             -> Eff effs (Package term)
parsePackage parser preludeFile project@Project{..} = do
  prelude <- traverse (parseModule parser Nothing) preludeFile
  p <- parseModules parser project
  trace ("project: " <> show p) $ pure (Package.fromModules n Nothing prelude (length projectEntryPoints) p)
  where
    n = name (projectName project)

    -- | Parse all files in a project into 'Module's.
    parseModules :: Members '[Distribute WrappedTask, Files, Task] effs => Parser term -> Project -> Eff effs [Module term]
    parseModules parser Project{..} = distributeFor (projectEntryPoints <> projectFiles) (WrapTask . parseModule parser (Just projectRootDir))

-- | Parse a file into a 'Module'.
parseModule :: Members '[Files, Task] effs => Parser term -> Maybe FilePath -> File -> Eff effs (Module term)
parseModule parser rootDir file = do
  blob <- readBlob file
  moduleForBlob rootDir blob <$> parse parser blob


type ImportGraphAnalysis term
  = ImportGraphing
  ( BadAddresses
  ( BadModuleResolutions
  ( BadVariables
  ( BadValues
  ( BadSyntax
  ( Erroring (Analysis.LoadError term)
  ( Evaluating
    (Located Precise term)
    term
    (Value (Located Precise term)))))))))

-- | Render the import graph for a given 'Package'.
graphImports :: ( Show ann
                , Ord ann
                , Apply Analysis.Declarations1 syntax
                , Apply Analysis.Evaluatable syntax
                , Apply FreeVariables1 syntax
                , Apply Functor syntax
                , Apply Ord1 syntax
                , Apply Eq1 syntax
                , Apply Show1 syntax
                , Members '[Exc SomeException, Task] effs
                )
             => Package (Term (Union syntax) ann) -> Eff effs Graph
graphImports package = analyze (Analysis.evaluatePackage package `asAnalysisForTypeOfPackage` package) >>= extractGraph
  where
    asAnalysisForTypeOfPackage :: ImportGraphAnalysis term effs value
                               -> Package term
                               -> ImportGraphAnalysis term effs value
    asAnalysisForTypeOfPackage = const

    extractGraph result = case result of
      (Right (Right ((_, graph), _)), _) -> pure graph
      _ -> throwError (toException (Exc.ErrorCall ("graphImports: import graph rendering failed " <> show result)))
