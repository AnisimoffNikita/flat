{-# LANGUAGE BangPatterns        #-}
{-# LANGUAGE CPP                 #-}
{-# LANGUAGE MagicHash           #-}
{-# LANGUAGE MultiWayIf          #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TupleSections       #-}
{-# LANGUAGE UnboxedTuples       #-}

-- |Encoding Primitives
module Data.Flat.Encoder.Prim
  ( eBits16F
  , eBitsF
  , eFloatF
  , eDoubleF
  #ifndef ghcjs_HOST_OS
  , eUTF16F
  #endif
  , eUTF8F
  , eCharF
  , eNaturalF
  , eIntegerF
  , eInt64F
  , eInt32F
  , eIntF
  , eInt16F
  , eInt8F
  , eWordF
  , eWord64F
  , eWord32F
  , eWord16F
  , eBytesF
  , eLazyBytesF
  , eShortBytesF
  , eWord8F
  , eFillerF
  , eBoolF
  , eTrueF
  , eFalseF
  , varWordF
  , w7l
    -- * Exported for testing only
  , eWord32BEF
  , eWord64BEF
  , eWord32E
  , eWord64E
  ) where

import           Control.Monad
import qualified Data.ByteString                as B
import qualified Data.ByteString.Lazy           as L
import qualified Data.ByteString.Lazy.Internal  as L
import qualified Data.ByteString.Short.Internal as SBS
import           Data.Char
import           Data.Flat.Encoder.Types
import           Data.Flat.Endian
import           Data.Flat.Memory
import           Data.Flat.Types
import           Data.FloatCast
import           Data.Primitive.ByteArray
import qualified Data.Text                      as T
import qualified Data.Text.Array                as TA
import qualified Data.Text.Encoding             as TE
import qualified Data.Text.Internal             as TI
import           Data.ZigZag
import           Foreign
-- import Debug.Trace
#include "MachDeps.h"
-- traceShowId :: a -> a
-- traceShowId = id
{-# INLINE eFloatF #-}
eFloatF :: Float -> Prim
eFloatF = eWord32BEF . floatToWord

{-# INLINE eDoubleF #-}
eDoubleF :: Double -> Prim
eDoubleF = eWord64BEF . doubleToWord

{-# INLINE eWord64BEF #-}
eWord64BEF :: Word64 -> Prim
eWord64BEF = eWord64E toBE64

{-# INLINE eWord32BEF #-}
eWord32BEF :: Word32 -> Prim
eWord32BEF = eWord32E toBE32

{-# INLINE eCharF #-}
eCharF :: Char -> Prim
eCharF = eWord32F . fromIntegral . ord

{-# INLINE eWordF #-}
eWordF :: Word -> Prim
{-# INLINE eIntF #-}
eIntF :: Int -> Prim
#if WORD_SIZE_IN_BITS == 64
eWordF = eWord64F . (fromIntegral :: Word -> Word64)

eIntF = eInt64F . (fromIntegral :: Int -> Int64)
#elif WORD_SIZE_IN_BITS == 32
eWordF = eWord32F . (fromIntegral :: Word -> Word32)

eIntF = eInt32F . (fromIntegral :: Int -> Int32)
#else
#error expected WORD_SIZE_IN_BITS to be 32 or 64
#endif
{-# INLINE eInt8F #-}
eInt8F :: Int8 -> Prim
eInt8F = eWord8F . zzEncode

{-# INLINE eInt16F #-}
eInt16F :: Int16 -> Prim
eInt16F = eWord16F . zzEncode

{-# INLINE eInt32F #-}
eInt32F :: Int32 -> Prim
eInt32F = eWord32F . zzEncode

{-# INLINE eInt64F #-}
eInt64F :: Int64 -> Prim
eInt64F = eWord64F . zzEncode

{-# INLINE eIntegerF #-}
eIntegerF :: Integer -> Prim
eIntegerF = eIntegralF . zzEncodeInteger

{-# INLINE eNaturalF #-}
eNaturalF :: Natural -> Prim
eNaturalF = eIntegralF . toInteger

{-# INLINE eIntegralF #-}
eIntegralF :: (Bits t, Integral t) => t -> Prim
eIntegralF t =
  let vs = w7l t
   in eIntegralW vs

w7l :: (Bits t, Integral t) => t -> [Word8]
w7l t =
  let l = low7 t
      t' = t `unsafeShiftR` 7
   in if t' == 0
        then [l]
        else w7 l : w7l t'
  where
    {-# INLINE w7 #-}
    --lowByte :: (Bits t, Num t) => t -> Word8
    w7 :: Word8 -> Word8
    w7 l = l .|. 0x80

-- Encode as data NEList = Elem Word7 | Cons Word7 List
{-# INLINE eIntegralW #-}
eIntegralW :: [Word8] -> Prim
eIntegralW vs s@(S op _ o)
  | o == 0 = foldM pokeWord' op vs >>= \op' -> return (S op' 0 0)
  | otherwise = foldM (flip eWord8F) s vs

{-# INLINE eWord8F #-}
eWord8F :: Word8 -> Prim
eWord8F t s@(S op _ o)
  | o == 0 = pokeWord op t
  | otherwise = pokeByteUnaligned t s

{-# INLINE eWord32E #-}
eWord32E :: (Word32 -> Word32) -> Word32 -> Prim
eWord32E conv t (S op w o)
  | o == 0 = pokeW conv op t >> skipBytes op 4
  | otherwise =
    pokeW conv op (asWord32 w `unsafeShiftL` 24 .|. t `unsafeShiftR` o) >>
    return (S (plusPtr op 4) (asWord8 t `unsafeShiftL` (8 - o)) o)

{-# INLINE eWord64E #-}
eWord64E :: (Word64 -> Word64) -> Word64 -> Prim
eWord64E conv t (S op w o)
  | o == 0 = poke64 conv op t >> skipBytes op 8
  | otherwise =
    poke64 conv op (asWord64 w `unsafeShiftL` 56 .|. t `unsafeShiftR` o) >>
    return (S (plusPtr op 8) (asWord8 t `unsafeShiftL` (8 - o)) o)

{-# INLINE eWord16F #-}
eWord16F :: Word16 -> Prim
eWord16F = varWordF

{-# INLINE eWord32F #-}
eWord32F :: Word32 -> Prim
eWord32F = varWordF

{-# INLINE eWord64F #-}
eWord64F :: Word64 -> Prim
eWord64F = varWordF

{-# INLINE varWordF #-}
varWordF :: (Bits t, Integral t) => t -> Prim
varWordF t s@(S _ _ o)
  | o == 0 = varWord pokeByteAligned t s
  | otherwise = varWord pokeByteUnaligned t s

{-# INLINE varWord #-}
varWord :: (Bits t, Integral t) => (Word8 -> Prim) -> t -> Prim
varWord writeByte t s
  | t < 128 = writeByte (fromIntegral t) s
  | t < 16384 = varWord2_ writeByte t s
  | t < 2097152 = varWord3_ writeByte t s
  | otherwise = varWordN_ writeByte t s
  where
    {-# INLINE varWord2_ #-}
      -- TODO: optimise, using a single Write16?
    varWord2_ writeByte t s =
      writeByte (fromIntegral t .|. 0x80) s >>=
      writeByte (fromIntegral (t `unsafeShiftR` 7) .&. 0x7F)
    {-# INLINE varWord3_ #-}
    varWord3_ writeByte t s =
      writeByte (fromIntegral t .|. 0x80) s >>=
      writeByte (fromIntegral (t `unsafeShiftR` 7) .|. 0x80) >>=
      writeByte (fromIntegral (t `unsafeShiftR` 14) .&. 0x7F)

-- {-# INLINE varWordN #-}
varWordN_ :: (Bits t, Integral t) => (Word8 -> Prim) -> t -> Prim
varWordN_ writeByte = go
  where
    go !v !st =
      let !l = low7 v
          !v' = v `unsafeShiftR` 7
       in if v' == 0
            then writeByte l st
            else writeByte (l .|. 0x80) st >>= go v'

{-# INLINE low7 #-}
low7 :: (Integral a) => a -> Word8
low7 t = fromIntegral t .&. 0x7F

-- | Encode text as UTF8 and encode the result as an array of bytes
-- PROB: encodeUtf8 calls a C primitive, not compatible with GHCJS
eUTF8F :: T.Text -> Prim
eUTF8F = eBytesF . TE.encodeUtf8
-- PROB: Not compatible with GHCJS
-- | Encode text as UTF16 and encode the result as an array of bytes
-- Efficient, as Text is already internally encoded as UTF16.
#ifndef ghcjs_HOST_OS
eUTF16F :: T.Text -> Prim
eUTF16F t = eFillerF >=> eUTF16F_ t
  where
    eUTF16F_ !(TI.Text (TA.Array array) w16Off w16Len) s =
      writeArray array (2 * w16Off) (2 * w16Len) (nextPtr s)
#endif
eLazyBytesF :: L.ByteString -> Prim
eLazyBytesF bs = eFillerF >=> \s -> write bs (nextPtr s)
    -- Single copy
  where
    write lbs op = do
      case lbs of
        L.Chunk h t -> writeBS h op >>= write t
        L.Empty     -> pokeWord op 0

{-# INLINE eShortBytesF #-}
eShortBytesF :: SBS.ShortByteString -> Prim
eShortBytesF bs = eFillerF >=> eShortBytesF_ bs

eShortBytesF_ :: SBS.ShortByteString -> Prim
eShortBytesF_ bs@(SBS.SBS arr) =
  \(S op _ 0) -> writeArray arr 0 (SBS.length bs) op

-- data Array a = Array0 | Array1 a ... | Array255 ...
writeArray :: ByteArray# -> Int -> Int -> Ptr Word8 -> IO S
writeArray arr soff slen sop = do
  op' <- go soff slen sop
  pokeWord op' 0
  where
    go !off !len !op
      | len == 0 = return op
      | otherwise =
        let l = min 255 len
         in pokeWord' op (fromIntegral l) >>= pokeByteArray arr off l >>=
            go (off + l) (len - l)

eBytesF :: B.ByteString -> Prim
eBytesF bs = eFillerF >=> eBytesF_
  where
    eBytesF_ s = do
      op' <- writeBS bs (nextPtr s)
      pokeWord op' 0

-- |Encode up to 9 bits
{-# INLINE eBits16F #-}
eBits16F :: NumBits -> Word16 -> Prim
--eBits16F numBits code | numBits >8 = eBitsF (numBits-8) (fromIntegral $ code `unsafeShiftR` 8) >=> eBitsF 8 (fromIntegral code)
-- eBits16F _ _ = eFalseF
eBits16F 9 code =
  eBitsF 1 (fromIntegral $ code `unsafeShiftR` 8) >=>
  eBitsF_ 8 (fromIntegral code)
eBits16F numBits code = eBitsF numBits (fromIntegral code)

-- |Encode up to 8 bits.
{-# INLINE eBitsF #-}
eBitsF :: NumBits -> Word8 -> Prim
eBitsF 1 0 = eFalseF
eBitsF 1 1 = eTrueF
eBitsF 2 0 = eFalseF >=> eFalseF
eBitsF 2 1 = eFalseF >=> eTrueF
eBitsF 2 2 = eTrueF >=> eFalseF
eBitsF 2 3 = eTrueF >=> eTrueF
eBitsF n t = eBitsF_ n t

{-
eBits Example:
Before:
n = 6
t = 00.101011
o = 3
w = 111.00000

After:
[ptr] = w(111)t(10101)
w' = t(1)0000000
o'= 1

o'=3+6=9
f = 8-9 = -1
o'' = 1
8-o''=7

if n=8,o=3:
o'=11
f=8-11=-3
o''=3
8-o''=5
-}
-- {-# NOINLINE eBitsF_ #-}
eBitsF_ :: NumBits -> Word8 -> Prim
eBitsF_ n t =
  \(S op w o) ->
    let o' = o + n -- used bits
        f = 8 - o' -- remaining free bits
     in if | f > 0 -> return $ S op (w .|. (t `unsafeShiftL` f)) o'
           | f == 0 -> pokeWord op (w .|. t)
           | otherwise ->
             let o'' = -f
              in poke op (w .|. (t `unsafeShiftR` o'')) >>
                 return (S (plusPtr op 1) (t `unsafeShiftL` (8 - o'')) o'')

{-# INLINE eBoolF #-}
eBoolF :: Bool -> Prim
eBoolF False = eFalseF
eBoolF True  = eTrueF

{-# INLINE eTrueF #-}
eTrueF :: Prim
eTrueF (S op w o)
  | o == 7 = pokeWord op (w .|. 1)
  | otherwise = return (S op (w .|. 128 `unsafeShiftR` o) (o + 1))

{-# INLINE eFalseF #-}
eFalseF :: Prim
eFalseF (S op w o)
  | o == 7 = pokeWord op w
  | otherwise = return (S op w (o + 1))

{-# INLINE eFillerF #-}
eFillerF :: Prim
eFillerF (S op w _) = pokeWord op (w .|. 1)

-- {-# INLINE poke16 #-}
-- TODO TEST
-- poke16 :: Word16 -> Prim
-- poke16 t (S op w o) | o == 0 = poke op w >> skipBytes op 2
{-# INLINE pokeByteUnaligned #-}
pokeByteUnaligned :: Word8 -> Prim
pokeByteUnaligned t (S op w o) =
  poke op (w .|. (t `unsafeShiftR` o)) >>
  return (S (plusPtr op 1) (t `unsafeShiftL` (8 - o)) o)

{-# INLINE pokeByteAligned #-}
pokeByteAligned :: Word8 -> Prim
pokeByteAligned t (S op _ _) = pokeWord op t

{-# INLINE pokeWord #-}
pokeWord :: Storable a => Ptr a -> a -> IO S
pokeWord op w = poke op w >> skipByte op

{-# INLINE pokeWord' #-}
pokeWord' :: Storable a => Ptr a -> a -> IO (Ptr b)
pokeWord' op w = poke op w >> return (plusPtr op 1)

{-# INLINE pokeW #-}
pokeW :: Storable a => (t -> a) -> Ptr a1 -> t -> IO ()
pokeW conv op t = poke (castPtr op) (conv t)

{-# INLINE poke64 #-}
poke64 :: (t -> Word64) -> Ptr a -> t -> IO ()
poke64 conv op t = poke (castPtr op) (fix64 . conv $ t)

{-# INLINE skipByte #-}
skipByte :: Monad m => Ptr a -> m S
skipByte op = return (S (plusPtr op 1) 0 0)

{-# INLINE skipBytes #-}
skipBytes :: Monad m => Ptr a -> Int -> m S
skipBytes op n = return (S (plusPtr op n) 0 0)

--{-# INLINE nextByteW #-}
--nextByteW op w = return (S (plusPtr op 1) 0 0)
writeBS :: B.ByteString -> Ptr Word8 -> IO (Ptr Word8)
writeBS bs op -- @(BS.PS foreignPointer sourceOffset sourceLength) op
  | B.length bs == 0 = return op
  | otherwise =
    let (h, t) = B.splitAt 255 bs
     in pokeWord' op (fromIntegral $ B.length h :: Word8) >>= pokeByteString h >>=
        writeBS t
    -- 2X slower (why?)
    -- withForeignPtr foreignPointer goS
    --   where
    --     goS sourcePointer = go op (sourcePointer `plusPtr` sourceOffset) sourceLength
    --       where
    --         go !op !off !len | len == 0 = return op
    --                          | otherwise = do
    --                           let l = min 255 len
    --                           op' <- pokeWord' op (fromIntegral l)
    --                           BS.memcpy op' off l
    --                           go (op' `plusPtr` l) (off `plusPtr` l) (len-l)

{-# INLINE asWord64 #-}
asWord64 :: Integral a => a -> Word64
asWord64 = fromIntegral

{-# INLINE asWord32 #-}
asWord32 :: Integral a => a -> Word32
asWord32 = fromIntegral

{-# INLINE asWord8 #-}
asWord8 :: Integral a => a -> Word8
asWord8 = fromIntegral
