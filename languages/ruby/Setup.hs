import Distribution.Simple
import Distribution.PackageDescription
import Distribution.Simple.Setup
import Distribution.Simple.Utils
import Distribution.Simple.LocalBuildInfo
import Data.Maybe
import System.Directory
import System.FilePath.Posix

main = defaultMainWithHooks simpleUserHooks {
  preConf = makeScannerLib,
  confHook = \a f -> confHook simpleUserHooks a f >>= updateExtraLibDirs,
  postClean = cleanScannerLib
}

makeScannerLib :: Args -> ConfigFlags -> IO HookedBuildInfo
makeScannerLib _ flags = do
  let verbosity = fromFlag $ configVerbosity flags
  rawSystemExit verbosity "env" ["mkdir", "-p", "lib"]
  rawSystemExit verbosity "env" ["gcc", "-std=c++11", "-Ivendor/tree-sitter-ruby/src/", "-fPIC", "vendor/tree-sitter-ruby/src/scanner.cc", "-c", "-o", "lib/scanner.o"]
  rawSystemExit verbosity "env" ["ar", "rcvs", "lib/libscanner.a", "lib/scanner.o"]
  pure emptyHookedBuildInfo

updateExtraLibDirs :: LocalBuildInfo -> IO LocalBuildInfo
updateExtraLibDirs localBuildInfo = do
  let packageDescription = localPkgDescr localBuildInfo
      lib = fromJust $ library packageDescription
      libBuild = libBuildInfo lib
  dir <- getCurrentDirectory
  pure localBuildInfo {
    localPkgDescr = packageDescription {
      library = Just $ lib {
        libBuildInfo = libBuild {
          extraLibDirs = (dir </> "lib") : extraLibDirs libBuild
        }
      }
    }
  }

cleanScannerLib :: Args -> CleanFlags -> PackageDescription -> () -> IO ()
cleanScannerLib _ flags _ _ = do
  let verbosity = fromFlag $ cleanVerbosity flags
  dir <- getCurrentDirectory
  rawSystemExit verbosity "env" ["rm", "-rf", dir </> "lib"]
