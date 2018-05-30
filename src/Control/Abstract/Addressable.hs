{-# LANGUAGE GADTs, RankNTypes, TypeFamilies, TypeOperators, UndecidableInstances #-}
module Control.Abstract.Addressable
( Addressable(..)
) where

import Control.Abstract.Context
import Control.Abstract.Evaluator
import Control.Abstract.Hole
import Data.Abstract.Address
import Data.Abstract.Name
import Prologue

-- | Defines allocation and dereferencing of 'Address'es in a 'Heap'.
class (Ord location, Show location) => Addressable location effects where
  -- | The type into which stored values will be written for a given location type.
  type family Cell location :: * -> *

  allocCell :: Name -> Evaluator location value effects location
  derefCell :: location -> Cell location value -> Evaluator location value effects (Maybe value)


-- | 'Precise' locations are always allocated a fresh 'Address', and dereference to the 'Latest' value written.
instance Member Fresh effects => Addressable Precise effects where
  type Cell Precise = Latest

  allocCell _ = Precise <$> fresh
  derefCell _ = pure . getLast . unLatest

-- | 'Monovariant' locations allocate one 'Address' per unique variable name, and dereference once per stored value, nondeterministically.
instance Member NonDet effects => Addressable Monovariant effects where
  type Cell Monovariant = All

  allocCell = pure . Monovariant
  derefCell _ = traverse (foldMapA pure) . nonEmpty . toList

-- | 'Located' locations allocate & dereference using the underlying location, contextualizing locations with the current 'PackageInfo' & 'ModuleInfo'.
instance (Addressable location effects, Member (Reader ModuleInfo) effects, Member (Reader PackageInfo) effects) => Addressable (Located location) effects where
  type Cell (Located location) = Cell location

  allocCell name = relocate (Located <$> allocCell name <*> currentPackage <*> currentModule)
  derefCell (Located loc _ _) = relocate . derefCell loc

instance Addressable location effects => Addressable (Hole location) effects where
  type Cell (Hole location) = Cell location

  allocCell name = relocate (Total <$> allocCell name)
  derefCell (Total loc) = relocate . derefCell loc
  derefCell Partial     = const (pure Nothing)

relocate :: Evaluator location1 value effects a -> Evaluator location2 value effects a
relocate = raiseEff . lowerEff
