{-# LANGUAGE
    RankNTypes
  , ScopedTypeVariables
  , DeriveGeneric
  #-}

module Control.Concurrent.Async.Every where

import Data.Maybe (fromMaybe)
import Control.Monad (forever)
import Control.Exception (Exception, catch)
import Control.Concurrent (threadDelay)
import Control.Concurrent.Async (async, Async, cancelWith)
import Control.Concurrent.STM (atomically)
import Control.Concurrent.STM.TVar (newTVarIO, readTVar, writeTVar)
import Control.Concurrent.STM.TChan (TChan, newTChanIO, readTChan, writeTChan)
import GHC.Generics (Generic)



-- | Spawn a process forever
every :: Int -- ^ time difference in microseconds
      -> Maybe Int -- ^ initial delay before first invocation
      -> IO a
      -> IO (Async a)
every interDelay mInitDelay =
  let timeToDelay soFar
        | soFar == 0 = fromMaybe 0 mInitDelay
        | otherwise  = interDelay
  in  everyFunc timeToDelay


everyForking :: Int
             -> Maybe Int
             -> IO a
             -> IO (Async (), TChan (Async a))
everyForking interDelay mInitDelay =
  let timeToDelay soFar
        | soFar == 0 = fromMaybe 0 mInitDelay
        | otherwise  = interDelay
  in  everyFuncForking timeToDelay


everyFunc :: forall a
           . (Int -> Int) -- ^ function from total time spent, to the time to delay from /now/
          -> IO a
          -> IO (Async a)
everyFunc timeToDelay x = do
  totalTimeSpent <- newTVarIO 0
  async $
    let thread = forever $ do
          x
          toGo <- atomically $ do
            soFar <- readTVar totalTimeSpent
            let toGo' = timeToDelay soFar
            writeTVar totalTimeSpent (soFar + toGo')
            pure toGo'
          threadDelay toGo
        resetter :: EveryException -> IO a
        resetter (EveryExceptionReset mThreadDelay) = do
          threadDelay $ fromMaybe 0 mThreadDelay
          thread
    in  thread `catch` resetter


-- | A version of 'everyFunc' which forks /every/ time *coolshades*.
everyFuncForking :: forall a
                  . (Int -> Int)
                 -> IO a
                 -> IO (Async (), TChan (Async a))
everyFuncForking timeToDelay x = do
  forkedChan <- newTChanIO
  mainThread <- everyFunc timeToDelay $ do
    latestThread <- async x
    atomically $ writeTChan forkedChan latestThread
  pure (mainThread,forkedChan)


reset :: Maybe Int -> Async a -> IO ()
reset mDelay chan = cancelWith chan (EveryExceptionReset mDelay)


data EveryException = EveryExceptionReset (Maybe Int)
  deriving (Show, Eq, Generic)

instance Exception EveryException
