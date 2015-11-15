{-# LANGUAGE CPP #-}
-----------------------------------------------------------------------------
--
-- Module      :  Language.Javascript.JSaddle.Monad
-- Copyright   :  (c) Hamish Mackenzie
-- License     :  MIT
--
-- Maintainer  :  Hamish Mackenzie <Hamish.K.Mackenzie@googlemail.com>
--
-- | JSM monad keeps track of the JavaScript context
--
-----------------------------------------------------------------------------

module Language.Javascript.JSaddle.Monad (
  -- * Types
    JSM(..)
  , JSContextRef

  -- * Running JSaddle given a DOM Window
  , runJSaddle
  , runJSaddle_

  -- * Exception Handling
  , catchval
  , catch
) where

import Prelude hiding (catch, read)
import Control.Monad.Trans.Reader (runReaderT, ask, ReaderT(..))
import Language.Javascript.JSaddle.Types
       (JSVal(..), MutableJSArray(..), JSContextRef)
import Control.Monad.IO.Class (MonadIO(..))
#if (defined(ghcjs_HOST_OS) && defined(USE_JAVASCRIPTFFI)) || !defined(USE_WEBKIT)
import GHCJS.Types (isUndefined, isNull)
import qualified JavaScript.Array as Array (create, read)
#else
import Foreign (nullPtr, alloca)
import Foreign.Storable (Storable(..))
import Graphics.UI.Gtk.WebKit.Types
       (WebView(..))
import Graphics.UI.Gtk.WebKit.WebView
       (webViewGetMainFrame)
import Graphics.UI.Gtk.WebKit.JavaScriptCore.WebFrame
       (webFrameGetGlobalContext)
#endif
import qualified Control.Exception as E (Exception, catch)
import Control.Monad (void)

-- | The @JSM@ monad keeps track of the JavaScript context.
--
-- Given a @JSM@ function and a 'JSContextRef' you can run the
-- function like this...
--
-- > runReaderT jsmFunction javaScriptContext
--
-- For an example of how to set up WebKitGTK+ see tests/TestJSaddle.hs
type JSM = ReaderT JSContextRef IO

-- | Wrapped version of 'E.catch' that runs in a MonadIO that works
--   a bit better with 'JSM'
catch :: (MonadIO m, E.Exception e)
      => ReaderT r IO b
      -> (e -> ReaderT r IO b)
      -> ReaderT r m b
t `catch` c = do
    r <- ask
    liftIO (runReaderT t r `E.catch` \e -> runReaderT (c e) r)
{-# INLINE catch #-}

-- | Handle JavaScriptCore functions that take a MutableJSArray in order
--   to throw exceptions.
catchval :: (MutableJSArray -> JSM a) -> (JSVal -> JSM a) -> JSM a
catchval f catcher = do
#if (defined(ghcjs_HOST_OS) && defined(USE_JAVASCRIPTFFI)) || !defined(USE_WEBKIT)
    pexc   <- liftIO Array.create
    result <- f pexc
    exc    <- liftIO $ Array.read 0 pexc
    if isUndefined exc || isNull exc
        then return result
        else catcher exc
#else
    gctxt <- ask
    liftIO . alloca $ \pexc -> flip runReaderT gctxt $ do
        liftIO $ poke pexc nullPtr
        result <- f pexc
        exc <- liftIO $ peek pexc
        if exc == nullPtr
            then return result
            else catcher exc
#endif

#if (defined(ghcjs_HOST_OS) && defined(USE_JAVASCRIPTFFI)) || !defined(USE_WEBKIT)
runJSaddle :: w -> JSM a -> IO a
runJSaddle _ f = runReaderT f ()
#else
runJSaddle :: WebView -> JSM a -> IO a
runJSaddle webView f = do
    gctxt <- webViewGetMainFrame webView >>= webFrameGetGlobalContext
    runReaderT f gctxt
#endif
{-# INLINE runJSaddle #-}

runJSaddle_ w f = void $ runJSaddle w f
{-# INLINE runJSaddle_ #-}
