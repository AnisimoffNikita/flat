
[![Build Status](https://travis-ci.org/Quid2/flat.svg?branch=master)](https://travis-ci.org/Quid2/flat)
[![Hackage version](https://img.shields.io/hackage/v/flat.svg)](http://hackage.haskell.org/package/flat)
[![Stackage LTS 6](http://stackage.org/package/flat/badge/lts-6)](http://stackage.org/lts/package/flat)
[![Stackage LTS 9](http://stackage.org/package/flat/badge/lts-9)](http://stackage.org/lts/package/flat)
[![Stackage LTS 11](http://stackage.org/package/flat/badge/lts-11)](http://stackage.org/lts/package/flat)
[![Stackage LTS 12](http://stackage.org/package/flat/badge/lts-12)](http://stackage.org/lts/package/flat)
[![Stackage Nightly](http://stackage.org/package/flat/badge/nightly)](http://stackage.org/nightly/package/flat)

Haskell implementation of [Flat](http://quid2.org/docs/Flat.pdf), a principled, portable and efficient binary data format ([specs](http://quid2.org)).

### How To Use It For Fun and Profit

To (de)serialise a data type, make it an instance of the `Flat` class.

There is `Generics` based support to automatically derive instances of additional types.

Let's see some code, we need a couple of extensions:

```haskell
{-# LANGUAGE DeriveGeneric, DeriveAnyClass #-}
```

Import the Flat library:

```haskell
import Data.Flat
```

Define a couple of custom data types, deriving Generic and Flat:

```haskell
data Direction = North | South | Center | East | West deriving (Show,Generic,Flat)
```

```haskell
data List a = Nil | Cons a (List a) deriving (Show,Generic,Flat)
```

For encoding, use `flat`, for decoding, use `unflat`:

```haskell
unflat . flat $ Cons North (Cons South Nil) :: Decoded (List Direction)
-> Right (Cons North (Cons South Nil))
```


For the decoding to work correctly, you will naturally need to know the type of the serialised data. This is ok for applications that do not require long-term storage and that do not need to communicate across independently evolving agents. For those who do, you will need to supplement `flat` with something like [zm](https://github.com/Quid2/zm).

#### Define Instances for Abstract/Primitive types

 A set of primitives are available to define `Flat` instances for abstract or primitive types.

 Instances for some common, primitive or abstract data types (Bool,Words,Int,String,Text,ByteStrings,Tuples, Lists, Sequences, Maps ..) are already defined in [Data.Flat.Instances](https://github.com/Quid2/flat/blob/master/src/Data/Flat/Instances.hs).

#### Optimal Bit-Encoding

A pecularity of Flat is that it uses an optimal bit-encoding rather than the usual byte-oriented one.

 To see this, let's define a pretty printing function: `bits` encodes a value as a sequence of bits, `prettyShow` displays it nicely:

```haskell
p :: Flat a => a -> String
p = prettyShow . bits
```

Now some encodings:

```haskell
p West
-> "111"
```


```haskell
p (Nil::List Direction)
-> "0"
```


```haskell
aList = Cons North (Cons South (Cons Center (Cons East (Cons West Nil))))
p aList
-> "10010111 01110111 10"
```


As you can see, `aList` fits in less than 3 bytes rather than 11 as would be the case with other Haskell byte oriented serialisation packages like `binary` or `store`.

For the serialisation to work with byte-oriented devices or storage, we need to add some padding:

```haskell
f :: Flat a => a -> String
f = prettyShow . paddedBits
```

```haskell
f West
-> "11100001"
```


```haskell
f (Nil::List Direction)
-> "00000001"
```


```haskell
f $ Cons North (Cons South (Cons Center (Cons East (Cons West Nil))))
-> "10010111 01110111 10000001"
```


The padding is a sequence of 0s terminated by a 1 running till the next byte boundary (if we are already at a byte boundary it will add an additional byte of value 1, that's unfortunate but there is a good reason for this, check the [specs](http://quid2.org/docs/Flat.pdf)).

Byte-padding is automatically added by the function `flat` and removed by `unflat`.

### Performance

For some hard data, see this [comparison of the major haskell serialisation libraries](https://github.com/haskell-perf/serialization).

Briefly:
 * Size: `flat` produces significantly smaller binaries than all other libraries (3/4 times usually)
 * Encoding: `store` is usually faster
 * Decoding: `store`, `flat` and `cereal` are usually faster
 * Transfer time (serialisation time + transport time on the network + deserialisation at the receiving end): `flat` is usually faster for all but the highest network speeds

### Compatibility

#### [GHC](https://www.haskell.org/ghc/) 

Tested with:
  * [ghc](https://www.haskell.org/ghc/) 7.10.3, 8.0.2, 8.2.2, 8.4.4 and 8.6.1 (x64)

Should also work with (not recently tested):
  * [ghc](https://www.haskell.org/ghc/) 7.10.3/LLVM 3.5.2 (Arm7)

####  [GHCJS](https://github.com/ghcjs/ghcjs)

Versions prior to 0.33 (so all versions currently on hackage) encode `Double` values incorrectly when they are not aligned with a byte boundary.

The version in github has been fixed and it passes all tests in the `flat` testsuite, except for those relative to short bytestrings (Data.ByteString.Short) that are unsupported by `ghcjs`.

A new hackage release is on its way.

You can build and test `flat` under `ghcjs` with:

`stack test --stack-yaml=stack-ghcjs.yaml`

#### [ETA](https://eta-lang.org/)

It compiles and seems to be working, though the full test suite could not be run due to Eta's issues compiling `quickcheck`.

### Installation

Get the latest stable version from [hackage](https://hackage.haskell.org/package/flat).

If you use ghcjs, use the github version, adding in your stack.yaml:

```
- location:
     git: https://github.com/Quid2/flat
     commit: 4795b519e2bd58127044d54b69dc371018607366
  extra-dep: true
```

### Acknowledgements

 `flat` reuses ideas and readapts code from various packages, mainly: `store`, `binary-bits` and `binary` and includes contributions from Justus Sagemüller.

### Known Bugs and Infelicities

* Long compilation times for generated Flat instances

During development, it's a good idea to turn optimisations off (`stack --fast` or `-O0` in the cabal file), this will completely eliminate the compilation time overhead.

* Data types with more than 256 constructors are unsupported

See also the [full list of open issues](https://github.com/Quid2/flat/issues).
