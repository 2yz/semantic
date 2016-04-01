module Renderer where

import Data.Functor.Both
import Diff
import Info
import Source

-- | A function that will render a diff, given the two source files.
type Renderer a b = Diff a Info -> Both SourceBlob -> b

data DiffArguments = DiffArguments { format :: Format, output :: Maybe FilePath, outputPath :: FilePath }

-- | The available types of diff rendering.
data Format = Split | Patch | JSON
