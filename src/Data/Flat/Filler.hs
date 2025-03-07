{-# LANGUAGE DeriveAnyClass      #-}
{-# LANGUAGE DeriveGeneric       #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE CPP       #-}

-- |Pre-value and post-value byte alignments
module Data.Flat.Filler (
    Filler(..),
    fillerLength,
    PreAligned(..),
    preAligned,
    PostAligned(..),
    postAligned,
    postAlignedDecoder
    ) where

import           Data.Flat.Class
import           Data.Flat.Encoder
import           Data.Flat.Decoder
import           Control.DeepSeq
import           Data.Typeable

-- |A meaningless sequence of 0 bits terminated with a 1 bit (easier to implement than the reverse)
-- Useful to align an encoded value at byte/word boundaries.
data Filler = FillerBit Filler
            | FillerEnd
  deriving (Show, Eq, Ord, Typeable, Generic, NFData)

-- |Use a special encoding for the filler
instance Flat Filler where
  encode _ = eFiller
  size = sFillerMax
  -- use generated decode

-- |A Post aligned value, a value followed by a filler
data PostAligned a = PostAligned { postValue :: a, postFiller :: Filler }
#ifdef ETA_VERSION    
  deriving (Show, Eq, Ord, Typeable, Generic, NFData)

instance Flat a => Flat (PostAligned a) where
  encode (PostAligned val fill) = trampolineEncoding (encode val) <> encode fill

#else
  deriving (Show, Eq, Ord, Typeable, Generic, NFData,Flat)
#endif
--  deriving (Show, Eq, Ord, Typeable, Generic, NFData,Flat)



-- |A Pre aligned value, a value preceded by a filler
data PreAligned a = PreAligned { preFiller :: Filler, preValue :: a }
  deriving (Show, Eq, Ord, Typeable, Generic, NFData, Flat)

-- |Length of a filler in bits
fillerLength :: Num a => Filler -> a
fillerLength FillerEnd     = 1
fillerLength (FillerBit f) = 1 + fillerLength f

-- |Post align a value
postAligned :: a -> PostAligned a
postAligned a = PostAligned a FillerEnd

-- |Pre align a value
preAligned :: a -> PreAligned a
preAligned = PreAligned FillerEnd

-- postAlignedDecoder :: Get a -> Get (PostAligned a)
postAlignedDecoder :: Get b -> Get b
postAlignedDecoder dec = do
  v <- dec
  _::Filler <- decode
  -- return (postAligned v)
  return v
