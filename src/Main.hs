{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell   #-}

-- | Simple Miso app with some buttons, some text, but most importantly: a
-- component that encapsulates the flatpickr widget. Uses the component pattern
-- described in this example: https://github.com/FPtje/miso-component-example
module Main where

import           Control.Concurrent ( forkIO )
import qualified Control.Concurrent.STM.TChan as STM
import           Control.Lens ( (^.), (.=), (%=), makeLenses, zoom, use )
import           Control.Monad ( forever, void )
import qualified Control.Monad.STM as STM
import           Data.Monoid ( (<>) )
import qualified Data.Time.Calendar as Time
import qualified Data.Time.Clock as Time
import           Data.Time.LocalTime ( LocalTime(..) )
import qualified Data.Time.LocalTime as Time
import qualified Data.Time.Format as Time
import qualified Flatpickr
import           Flatpickr ( Interface(..), Opts(..) )
import           Miso ( App(..), Transition )
import qualified Miso
import           Miso.Html
import qualified Miso.String as Miso

data Model
   = Model
     { _mFlatpickr        :: !Flatpickr.Model
       -- ^ The JS widget component.
     , _mFlatpickrVisible :: !Bool
       -- ^ Toggled by the "Toggle calendar visibility" button
     , _mDate             :: !Time.Day
       -- ^ The currently selected date
     }
     deriving ( Eq )

makeLenses ''Model

data Action
  = FlatpickrAction !(Flatpickr.Action Action)
    -- ^ Passes Actions to the Flatpickr widget component.
  | ToggleCalendarVisibility
  | PreviousDay
  | NextDay
  | DateChange !Time.Day
  -- ^ Thrown when the date is changed by the widget.
  | NoOp

main :: IO ()
main = do
    initModel <- initialModel
    actionChannel <- STM.newTChanIO

    Miso.startApp App
      { initialAction = NoOp
      , model         = initModel
      , update        = Miso.fromTransition . updateModel actionChannel
      , view          = viewModel
      , events        = Miso.defaultEvents
      , subs          = [sinkSub actionChannel]
      , mountPoint    = Nothing
      }

-- | Listens to some channel and throws everything it gets in the sink,
-- causing those actions to end up in the update function. The flatpickr
-- component needs this sink to add event listeners to the widget, for it
-- needs some way to get an action back into the update function when events
-- are fired.
sinkSub :: STM.TChan action -> Sub action model
sinkSub actionChannel _getModel sink = void $ forkIO $ forever $ do
    action <- STM.atomically $ STM.readTChan actionChannel
    sink action

initialModel :: IO Model
initialModel = do
    -- Initialise starting date to today
    curTime <- Time.getCurrentTime
    timeZone <- Time.getCurrentTimeZone

    let day :: Time.Day
        (LocalTime day _timeOfDay) = Time.utcToLocalTime timeZone curTime

    pure Model
      { _mFlatpickr        = Flatpickr.initialModel
      , _mFlatpickrVisible = True
      , _mDate             = day
      }

updateModel :: STM.TChan Action -> Action -> Transition Action Model ()
updateModel actionChannel action = case action of
    NoOp -> pure ()

    FlatpickrAction act -> do
      date <- use mDate
      zoom mFlatpickr $
        Flatpickr.updateModel (flatpickrIface date) sink act

    ToggleCalendarVisibility ->
      mFlatpickrVisible %= not

    PreviousDay -> do
      mDate %= Time.addDays (-1)
      date <- use mDate

      -- Update the widget with the new date
      zoom mFlatpickr $
        Flatpickr.updateModel
          (flatpickrIface date)
          sink
          (Flatpickr.SetDate date)


    NextDay -> do
      mDate %= Time.addDays 1
      date <- use mDate

      -- Update the widget with the new date
      zoom mFlatpickr $
        Flatpickr.updateModel
          (flatpickrIface date)
          sink
          (Flatpickr.SetDate date)

    DateChange day ->
      mDate .= day
  where
    sink = STM.atomically . STM.writeTChan actionChannel

viewModel :: Model -> View Action
viewModel m =
    div_ []
      ( viewCalendar m ++
        [ div_[]
          [ button_ [ onClick PreviousDay ] [ text "Previous day" ]
          , button_ [ onClick NextDay     ] [ text "Next day" ]
          ]
        , div_ []
          [ h1_ []
           [ text $ "Selected date: " <> Miso.toMisoString selectedDate
           ]
          ]
        , div_ []
          [ button_
            [ onClick ToggleCalendarVisibility ]
            [ text "Toggle calendar visibility" ]
          ]
        ]
      )
  where
    selectedDate = Time.formatTime Time.defaultTimeLocale "%F" $ m ^. mDate

-- | Show the calendar, but only when it's been set to be visible.
viewCalendar :: Model -> [View Action]
viewCalendar m
    | not (m ^. mFlatpickrVisible) = []
    | otherwise =
      [ Flatpickr.viewModel (flatpickrIface $ m ^. mDate)
      ]

-- | The Flatpickr component needs to know some things about the parent that
-- includes it. With the parent being this module, that information has to be
-- provided here.
flatpickrIface :: Time.Day -> Interface Action
flatpickrIface date =
    Interface
    { uniqueId      = "topLevelCalendar"
    , passAction    = FlatpickrAction
    , onChanged     = DateChange
    , noop          = NoOp
    , options       =
        Opts
        { weekNumbers = True
        , inline      = True
        , defaultDate =
            Miso.toMisoString $
            Time.formatTime Time.defaultTimeLocale "%F" date
        }
    }
