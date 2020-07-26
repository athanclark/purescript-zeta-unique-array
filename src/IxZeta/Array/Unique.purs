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


data ArrayUpdate value
  = ArrayAppend { index :: Int, valueNew :: value }
  | ArrayUpdate { index :: Int, valueOld :: value, valueNew :: value }
  | ArrayDelete { index :: Int, valueOld :: value }
  | ArrayMove { indexOld :: Int, indexNew :: Int, value :: value }
  | ArrayOverwrite { values :: UniqueArray value }

newtype IxSignalArray (rw :: # S.SCOPE) value = IxSignalArray
  { state :: Ref (UniqueArray value)
  , queue :: IxQueue (read :: Q.READ, write :: Q.WRITE) (ArrayUpdate value)
  }

instance signalScopeIxSignalArray :: S.SignalScope IxSignalArray where
  readOnly (IxSignalArray x) = IxSignalArray x
  writeOnly (IxSignalArray x) = IxSignalArray x
  allowReading (IxSignalArray x) = IxSignalArray x
  allowWriting (IxSignalArray x) = IxSignalArray x

new :: forall value. UniqueArray value -> Effect (IxSignalArray (read :: S.READ, write :: S.WRITE) value)
new xs = do
  state <- Ref.new xs
  queue <- IxQueue.new
  pure $ IxSignalArray { state, queue }

get :: forall rw value. IxSignalArray (read :: S.READ | rw) value -> Effect (UniqueArray value)
get (IxSignalArray {state}) = Ref.read state

append :: forall rw value. Eq value => value -> IxSignalArray (write :: S.WRITE | rw) value -> Effect Boolean
append x (IxSignalArray {state, queue}) = do
  xs <- Ref.read state
  case UniqueArray.snoc xs x of
    Nothing -> pure false
    Just xs' -> do
      Ref.write xs' state
      IxQueue.broadcast queue (ArrayAppend { index: UniqueArray.length xs, valueNew: x })
      pure true

appendExcept :: forall rw value. Eq value => Array String -> value -> IxSignalArray (write :: S.WRITE | rw) value -> Effect Boolean
appendExcept indicies x (IxSignalArray {state, queue}) = do
  xs <- Ref.read state
  case UniqueArray.snoc xs x of
    Nothing -> pure false
    Just xs' -> do
      Ref.write xs' state
      IxQueue.broadcastExcept queue indicies (ArrayAppend { index: UniqueArray.length xs, valueNew: x })
      pure true

update :: forall rw value. Eq value => Int -> (value -> value) -> IxSignalArray (write :: S.WRITE | rw) value -> Effect Boolean
update index f (IxSignalArray {state, queue}) = do
  xs <- Ref.read state
  case UniqueArray.index xs index of
    Nothing -> pure false
    Just x -> case UniqueArray.modifyAt index f xs of
      Nothing -> pure false
      Just xs' -> do
        Ref.write xs' state
        IxQueue.broadcast queue (ArrayUpdate {index, valueOld: x, valueNew: f x})
        pure true

updateExcept :: forall rw value. Eq value => Array String -> Int -> (value -> value) -> IxSignalArray (write :: S.WRITE | rw) value -> Effect Boolean
updateExcept indicies index f (IxSignalArray {state, queue}) = do
  xs <- Ref.read state
  case UniqueArray.index xs index of
    Nothing -> pure false
    Just x -> case UniqueArray.modifyAt index f xs of
      Nothing -> pure false
      Just xs' -> do
        Ref.write xs' state
        IxQueue.broadcastExcept queue indicies (ArrayUpdate {index, valueOld: x, valueNew: f x})
        pure true

delete :: forall rw value. Int -> IxSignalArray (write :: S.WRITE | rw) value -> Effect Boolean
delete index (IxSignalArray {state, queue}) = do
  xs <- Ref.read state
  case UniqueArray.index xs index of
    Nothing -> pure false
    Just x -> case UniqueArray.deleteAt index xs of
      Nothing -> pure false
      Just xs' -> do
        Ref.write xs' state
        IxQueue.broadcast queue (ArrayDelete {index, valueOld: x})
        pure true

deleteExcept :: forall rw value. Array String -> Int -> IxSignalArray (write :: S.WRITE | rw) value -> Effect Boolean
deleteExcept indicies index (IxSignalArray {state, queue}) = do
  xs <- Ref.read state
  case UniqueArray.index xs index of
    Nothing -> pure false
    Just x -> case UniqueArray.deleteAt index xs of
      Nothing -> pure false
      Just xs' -> do
        Ref.write xs' state
        IxQueue.broadcastExcept queue indicies (ArrayDelete {index, valueOld: x})
        pure true

overwrite :: forall rw value. UniqueArray value -> IxSignalArray (write :: S.WRITE | rw) value -> Effect Unit
overwrite values (IxSignalArray {state, queue}) = do
  Ref.write values state
  IxQueue.broadcast queue (ArrayOverwrite {values})

overwriteExcept :: forall rw value. Array String -> UniqueArray value -> IxSignalArray (write :: S.WRITE | rw) value -> Effect Unit
overwriteExcept indicies values (IxSignalArray {state, queue}) = do
  Ref.write values state
  IxQueue.broadcastExcept queue indicies (ArrayOverwrite {values})

move :: forall rw value. Eq value => Int -> Int -> IxSignalArray (write :: S.WRITE | rw) value -> Effect Boolean
move indexOld indexNew (IxSignalArray {state, queue}) = do
  xs <- Ref.read state
  case UniqueArray.index xs indexOld of
    Nothing -> pure false
    Just value -> case UniqueArray.deleteAt indexOld xs of
      Nothing -> pure false
      Just xs' -> case UniqueArray.insertAt indexNew value xs of
        Nothing -> pure false
        Just xs'' -> do
          Ref.write xs'' state
          IxQueue.broadcast queue (ArrayMove {indexOld, indexNew, value})
          pure true

moveExcept :: forall rw value. Eq value => Array String -> Int -> Int -> IxSignalArray (write :: S.WRITE | rw) value -> Effect Boolean
moveExcept indicies indexOld indexNew (IxSignalArray {state, queue}) = do
  xs <- Ref.read state
  case UniqueArray.index xs indexOld of
    Nothing -> pure false
    Just value -> case UniqueArray.deleteAt indexOld xs of
      Nothing -> pure false
      Just xs' -> case UniqueArray.insertAt indexNew value xs of
        Nothing -> pure false
        Just xs'' -> do
          Ref.write xs'' state
          IxQueue.broadcastExcept queue indicies (ArrayMove {indexOld, indexNew, value})
          pure true

subscribeLight :: forall rw value. String -> (ArrayUpdate value -> Effect Unit) -> IxSignalArray (read :: S.READ | rw) value -> Effect Unit
subscribeLight index handler (IxSignalArray {queue}) =
  IxQueue.on queue index handler

unsubscribe :: forall rw value. String -> IxSignalArray (read :: S.READ | rw) value -> Effect Boolean
unsubscribe index (IxSignalArray {queue}) =
  IxQueue.del queue index
