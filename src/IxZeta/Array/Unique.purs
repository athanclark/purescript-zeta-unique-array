module IxZeta.Array.Unique where

import Prelude
import Data.Maybe (Maybe (..))
import Data.Array.Unique (UniqueArray)
import Data.Array.Unique (snoc, insertAt, deleteAt, modifyAt, index, length) as UniqueArray
import Effect (Effect)
import Effect.Ref (Ref)
import Effect.Ref (new, read, write) as Ref
import Zeta.Types (READ, WRITE, kind SCOPE, class SignalScope) as S
import Queue.Types (READ, WRITE) as Q
import IxQueue (IxQueue)
import IxQueue (new, broadcast, broadcastExcept, on, del) as IxQueue


data UniqueArrayUpdate value
  = UniqueArrayAppend { index :: Int, valueNew :: value }
  | UniqueArrayUpdate { index :: Int, valueOld :: value, valueNew :: value }
  | UniqueArrayDelete { index :: Int, valueOld :: value }
  | UniqueArrayMove { indexOld :: Int, indexNew :: Int, value :: value }
  | UniqueArrayOverwrite { values :: UniqueArray value }

newtype IxSignalUniqueArray (rw :: # S.SCOPE) value = IxSignalUniqueArray
  { state :: Ref (UniqueArray value)
  , queue :: IxQueue (read :: Q.READ, write :: Q.WRITE) (UniqueArrayUpdate value)
  }

instance signalScopeIxSignalUniqueArray :: S.SignalScope IxSignalUniqueArray where
  readOnly (IxSignalUniqueArray x) = IxSignalUniqueArray x
  writeOnly (IxSignalUniqueArray x) = IxSignalUniqueArray x
  allowReading (IxSignalUniqueArray x) = IxSignalUniqueArray x
  allowWriting (IxSignalUniqueArray x) = IxSignalUniqueArray x

new :: forall value. UniqueArray value -> Effect (IxSignalUniqueArray (read :: S.READ, write :: S.WRITE) value)
new xs = do
  state <- Ref.new xs
  queue <- IxQueue.new
  pure $ IxSignalUniqueArray { state, queue }

get :: forall rw value. IxSignalUniqueArray (read :: S.READ | rw) value -> Effect (UniqueArray value)
get (IxSignalUniqueArray {state}) = Ref.read state

append :: forall rw value. Eq value => value -> IxSignalUniqueArray (write :: S.WRITE | rw) value -> Effect Boolean
append x (IxSignalUniqueArray {state, queue}) = do
  xs <- Ref.read state
  case UniqueArray.snoc xs x of
    Nothing -> pure false
    Just xs' -> do
      Ref.write xs' state
      IxQueue.broadcast queue (UniqueArrayAppend { index: UniqueArray.length xs, valueNew: x })
      pure true

appendExcept :: forall rw value. Eq value => Array String -> value -> IxSignalUniqueArray (write :: S.WRITE | rw) value -> Effect Boolean
appendExcept indicies x (IxSignalUniqueArray {state, queue}) = do
  xs <- Ref.read state
  case UniqueArray.snoc xs x of
    Nothing -> pure false
    Just xs' -> do
      Ref.write xs' state
      IxQueue.broadcastExcept queue indicies (UniqueArrayAppend { index: UniqueArray.length xs, valueNew: x })
      pure true

update :: forall rw value. Eq value => Int -> (value -> value) -> IxSignalUniqueArray (write :: S.WRITE | rw) value -> Effect Boolean
update index f (IxSignalUniqueArray {state, queue}) = do
  xs <- Ref.read state
  case UniqueArray.index xs index of
    Nothing -> pure false
    Just x -> case UniqueArray.modifyAt index f xs of
      Nothing -> pure false
      Just xs' -> do
        Ref.write xs' state
        IxQueue.broadcast queue (UniqueArrayUpdate {index, valueOld: x, valueNew: f x})
        pure true

updateExcept :: forall rw value. Eq value => Array String -> Int -> (value -> value) -> IxSignalUniqueArray (write :: S.WRITE | rw) value -> Effect Boolean
updateExcept indicies index f (IxSignalUniqueArray {state, queue}) = do
  xs <- Ref.read state
  case UniqueArray.index xs index of
    Nothing -> pure false
    Just x -> case UniqueArray.modifyAt index f xs of
      Nothing -> pure false
      Just xs' -> do
        Ref.write xs' state
        IxQueue.broadcastExcept queue indicies (UniqueArrayUpdate {index, valueOld: x, valueNew: f x})
        pure true

delete :: forall rw value. Int -> IxSignalUniqueArray (write :: S.WRITE | rw) value -> Effect Boolean
delete index (IxSignalUniqueArray {state, queue}) = do
  xs <- Ref.read state
  case UniqueArray.index xs index of
    Nothing -> pure false
    Just x -> case UniqueArray.deleteAt index xs of
      Nothing -> pure false
      Just xs' -> do
        Ref.write xs' state
        IxQueue.broadcast queue (UniqueArrayDelete {index, valueOld: x})
        pure true

deleteExcept :: forall rw value. Array String -> Int -> IxSignalUniqueArray (write :: S.WRITE | rw) value -> Effect Boolean
deleteExcept indicies index (IxSignalUniqueArray {state, queue}) = do
  xs <- Ref.read state
  case UniqueArray.index xs index of
    Nothing -> pure false
    Just x -> case UniqueArray.deleteAt index xs of
      Nothing -> pure false
      Just xs' -> do
        Ref.write xs' state
        IxQueue.broadcastExcept queue indicies (UniqueArrayDelete {index, valueOld: x})
        pure true

overwrite :: forall rw value. UniqueArray value -> IxSignalUniqueArray (write :: S.WRITE | rw) value -> Effect Unit
overwrite values (IxSignalUniqueArray {state, queue}) = do
  Ref.write values state
  IxQueue.broadcast queue (UniqueArrayOverwrite {values})

overwriteExcept :: forall rw value. Array String -> UniqueArray value -> IxSignalUniqueArray (write :: S.WRITE | rw) value -> Effect Unit
overwriteExcept indicies values (IxSignalUniqueArray {state, queue}) = do
  Ref.write values state
  IxQueue.broadcastExcept queue indicies (UniqueArrayOverwrite {values})

move :: forall rw value. Eq value => Int -> Int -> IxSignalUniqueArray (write :: S.WRITE | rw) value -> Effect Boolean
move indexOld indexNew (IxSignalUniqueArray {state, queue}) = do
  xs <- Ref.read state
  case UniqueArray.index xs indexOld of
    Nothing -> pure false
    Just value -> case UniqueArray.deleteAt indexOld xs of
      Nothing -> pure false
      Just xs' -> case UniqueArray.insertAt indexNew value xs of
        Nothing -> pure false
        Just xs'' -> do
          Ref.write xs'' state
          IxQueue.broadcast queue (UniqueArrayMove {indexOld, indexNew, value})
          pure true

moveExcept :: forall rw value. Eq value => Array String -> Int -> Int -> IxSignalUniqueArray (write :: S.WRITE | rw) value -> Effect Boolean
moveExcept indicies indexOld indexNew (IxSignalUniqueArray {state, queue}) = do
  xs <- Ref.read state
  case UniqueArray.index xs indexOld of
    Nothing -> pure false
    Just value -> case UniqueArray.deleteAt indexOld xs of
      Nothing -> pure false
      Just xs' -> case UniqueArray.insertAt indexNew value xs of
        Nothing -> pure false
        Just xs'' -> do
          Ref.write xs'' state
          IxQueue.broadcastExcept queue indicies (UniqueArrayMove {indexOld, indexNew, value})
          pure true

subscribeLight :: forall rw value. String -> (UniqueArrayUpdate value -> Effect Unit) -> IxSignalUniqueArray (read :: S.READ | rw) value -> Effect Unit
subscribeLight index handler (IxSignalUniqueArray {queue}) =
  IxQueue.on queue index handler

unsubscribe :: forall rw value. String -> IxSignalUniqueArray (read :: S.READ | rw) value -> Effect Boolean
unsubscribe index (IxSignalUniqueArray {queue}) =
  IxQueue.del queue index
