{- Tribal Wars 2 farmbot version 2022-03-11

   I search for barbarian villages around your villages and then attack them.

   When starting, I first open a new web browser window. This might take longer on the first run because I need to download the web browser software.
   When the web browser has opened, navigate to Tribal Wars 2 and log in to your account, so you see your villages.
   Then the browsers address bar will probably show an URL like https://es.tribalwars2.com/game.php?world=es77&character_id=123456#

   When I see the game is loaded, I start searching for barbarian villages.
   As soon I have found one, I begin attacking it, using the army presets that you configured in the game.
   To attack, I pick an army preset that matches the following three criteria:

   + The preset name contains the string 'farm'.
   + The preset is enabled for the currently selected village.
   + The village has enough units available for the preset.

   If multiple army presets match these criteria, I use the first one by alphabetical order.
   If no army preset matches this filter, I activate another village which has a matching preset and enough available units.
   If there is no village with a matching preset and enough units, I stop attacking.

   ## Configuration Settings

   All settings are optional; you only need them in case the defaults don't fit your use-case.
   Following is a list of available settings:

   + `number-of-farm-cycles` : Number of farm cycles before the bot stops. The default is only one (`1`) cycle.
   + `break-duration` : Duration of breaks between farm cycles, in minutes. You can also specify a range like `60 - 120`. The bot then picks a random value in this range.
   + `farm-barb-min-points`: Minimum points of barbarian villages to attack.
   + `farm-barb-max-distance`: Maximum distance of barbarian villages to attack.
   + `farm-avoid-coordinates`: List of village coordinates to avoid when farming. Here is an example with two coordinates: '567|456 413|593'. This filter applies to both target and sending villages.
   + `farm-player`: Name of a player/character to farm. By default, the bot only farms barbarians, but this setting allows you to also farm players.
   + `farm-army-preset-pattern`: Text for filtering the army presets to use for farm attacks. Army presets only pass the filter when their name contains this text.
   + `limit-outgoing-commands-per-village`: The maximum number of outgoing commands per village before the bot considers the village completed. By default, the bot will use up all available 50 outgoing commands per village. You can also specify a range like `45 - 48`. The bot then picks a random value in this range for each village.
   + `close-game-client-during-break`: Set this to 'yes' to make the bot close the game client/web browser during breaks.
   + `open-website-on-start`: Website to open when starting the web browser.

   When using more than one setting, start a new line for each setting in the text input field.
   Here is an example of `bot-settings` for three farm cycles with breaks of 20 to 40 minutes in between:

   ```
   number-of-farm-cycles = 3
   break-duration = 20 - 40
   ```

   To learn about the farmbot, see https://to.botlab.org/guide/app/tribal-wars-2-farmbot

-}
{-
   catalog-tags:tribal-wars-2,farmbot
   authors-forum-usernames:viir
-}


module Bot exposing
    ( State
    , botMain
    )

import BotLab.BotInterface_To_Host_20210823 as InterfaceToHost
import Common.AppSettings as AppSettings
import Common.Basics exposing (stringContainsIgnoringCase)
import Common.DecisionTree
    exposing
        ( DecisionPathNode
        , continueDecisionTree
        , describeBranch
        , endDecisionPath
        , unpackToDecisionStagesDescriptionsAndLeaf
        )
import Dict
import Json.Decode
import Json.Decode.Extra
import Json.Encode
import List.Extra
import Result.Extra
import String.Extra
import WebBrowser.BotFramework as BotFramework exposing (BotEvent, BotResponse)


initBotSettings : BotSettings
initBotSettings =
    { numberOfFarmCycles = 1
    , breakDurationMinutes = { minimum = 90, maximum = 120 }
    , farmBarbarianVillageMinimumPoints = Nothing
    , farmBarbarianVillageMaximumDistance = 50
    , farmAvoidCoordinates = []
    , playersToFarm = []
    , farmArmyPresetPatterns = []
    , limitOutgoingCommandsPerVillage = { minimum = 50, maximum = 50 }
    , webBrowserUserProfileId = "default"
    , closeGameClientDuringBreak = AppSettings.No
    , openWebsiteOnStart = Nothing
    }


parseBotSettings : String -> Result String BotSettings
parseBotSettings =
    AppSettings.parseSimpleListOfAssignmentsSeparatedByNewlines
        ([ ( "number-of-farm-cycles"
           , AppSettings.valueTypeInteger
                (\numberOfFarmCycles settings ->
                    { settings | numberOfFarmCycles = numberOfFarmCycles }
                )
           )
         , ( "break-duration"
           , parseBotSettingBreakDurationMinutes
           )
         , ( "farm-barb-min-points"
           , AppSettings.valueTypeInteger
                (\minimumPoints settings ->
                    { settings | farmBarbarianVillageMinimumPoints = Just minimumPoints }
                )
           )
         , ( "farm-barb-max-distance"
           , AppSettings.valueTypeInteger
                (\maxDistance settings ->
                    { settings | farmBarbarianVillageMaximumDistance = maxDistance }
                )
           )
         , ( "farm-avoid-coordinates"
           , parseSettingFarmAvoidCoordinates
           )
         , ( "farm-player"
           , AppSettings.valueTypeString
                (\playerName settings ->
                    { settings | playersToFarm = playerName :: settings.playersToFarm }
                )
           )
         , ( "farm-army-preset-pattern"
           , AppSettings.valueTypeString
                (\presetPattern settings ->
                    { settings | farmArmyPresetPatterns = presetPattern :: settings.farmArmyPresetPatterns }
                )
           )
         , ( "limit-outgoing-commands-per-village"
           , parseBotSettingLimitOutgoingCommandsPerVillage
           )
         , ( "web-browser-user-profile-id"
           , AppSettings.valueTypeString
                (\webBrowserUserProfileId settings ->
                    { settings | webBrowserUserProfileId = webBrowserUserProfileId }
                )
           )
         , ( "close-game-client-during-break"
           , AppSettings.valueTypeYesOrNo
                (\closeGameClientDuringBreak settings ->
                    { settings | closeGameClientDuringBreak = closeGameClientDuringBreak }
                )
           )
         , ( "open-website-on-start"
           , AppSettings.valueTypeString
                (\openWebsiteOnStart settings ->
                    { settings | openWebsiteOnStart = Just openWebsiteOnStart }
                )
           )
         ]
            |> Dict.fromList
        )
        initBotSettings


implicitSettingsFromExplicitSettings : BotSettings -> BotSettings
implicitSettingsFromExplicitSettings settings =
    { settings
        | farmArmyPresetPatterns =
            if settings.farmArmyPresetPatterns == [] then
                [ farmArmyPresetNamePatternDefault ]

            else
                settings.farmArmyPresetPatterns
    }


farmArmyPresetNamePatternDefault : String
farmArmyPresetNamePatternDefault =
    "farm"


restartGameClientInterval : Int
restartGameClientInterval =
    60 * 30


gameRootInformationQueryInterval : Int
gameRootInformationQueryInterval =
    60


waitDurationAfterReloadWebPage : Int
waitDurationAfterReloadWebPage =
    15


ownVillageInfoMaxAge : Int
ownVillageInfoMaxAge =
    600


selectedVillageInfoMaxAge : Int
selectedVillageInfoMaxAge =
    30


readFromGameTimeoutCountThresholdToRestart : Int
readFromGameTimeoutCountThresholdToRestart =
    5


switchToOtherVillageCommandCapacityMinimum : Int
switchToOtherVillageCommandCapacityMinimum =
    5


type alias BotState =
    { timeInMilliseconds : Int
    , settings : BotSettings
    , currentActivity : Maybe { beginTimeInMilliseconds : Int, decision : DecisionPathNode InFarmCycleResponse }
    , lastRequestToPageId : Int
    , pendingRequestToPageRequestId : Maybe String
    , lastRunJavascriptResult :
        Maybe
            { timeInMilliseconds : Int
            , response : BotFramework.RunJavascriptInCurrentPageResponseStructure
            , parseResult : Result Json.Decode.Error RootInformationStructure
            }
    , lastPageLocation : Maybe String
    , gameLastPageLocation : Maybe String
    , gameRootInformationResult : Maybe { timeInMilliseconds : Int, gameRootInformation : TribalWars2RootInformation }
    , ownVillagesDetails : Dict.Dict Int { timeInMilliseconds : Int, villageDetails : VillageDetails }
    , lastJumpToCoordinates : Maybe { timeInMilliseconds : Int, coordinates : VillageCoordinates }
    , coordinatesLastCheck : Dict.Dict ( Int, Int ) { timeInMilliseconds : Int, result : VillageByCoordinatesResult }
    , numberOfReadsFromCoordinates : Int
    , readFromGameConsecutiveTimeoutsCount : Int
    , farmState : FarmState
    , lastAttackTimeInMilliseconds : Maybe Int
    , lastActivatedVillageTimeInMilliseconds : Maybe Int
    , lastStartWebBrowserTimeInSeconds : Maybe Int
    , startWebBrowserCount : Int
    , completedFarmCycles : List FarmCycleConclusion
    , lastRequestReportListResult : Maybe RequestReportListResponseStructure
    , parseResponseError : Maybe Json.Decode.Error
    , cache_relativeCoordinatesToSearchForFarmsPartitions : List (List VillageCoordinates)
    }


type alias BotSettings =
    { numberOfFarmCycles : Int
    , breakDurationMinutes : IntervalInt
    , farmBarbarianVillageMinimumPoints : Maybe Int
    , farmBarbarianVillageMaximumDistance : Int
    , farmAvoidCoordinates : List VillageCoordinates
    , playersToFarm : List String
    , farmArmyPresetPatterns : List String
    , limitOutgoingCommandsPerVillage : IntervalInt
    , webBrowserUserProfileId : String
    , closeGameClientDuringBreak : AppSettings.YesOrNo
    , openWebsiteOnStart : Maybe String
    }


type alias FarmCycleState =
    { getArmyPresetsResult : Maybe (List ArmyPreset)
    , sentAttackByCoordinates : Dict.Dict ( Int, Int ) ()
    }


type alias FarmCycleConclusion =
    { beginTime : Int
    , completionTime : Int
    , attacksCount : Int
    , villagesResults : Dict.Dict Int VillageCompletedStructure
    }


type FarmState
    = InFarmCycle { beginTime : Int } FarmCycleState
    | InBreak { lastCycleCompletionTime : Int, nextCycleStartTime : Int }


type alias State =
    BotFramework.StateIncludingSetup BotState


type ResponseFromBrowser
    = RootInformation RootInformationStructure
    | ReadSelectedCharacterVillageDetailsResponse ReadSelectedCharacterVillageDetailsResponseStructure
    | VillagesByCoordinatesResponse VillagesByCoordinatesResponseStructure
    | GetPresetsResponse (List ArmyPreset)
    | ActivatedVillageResponse
    | SendPresetAttackToCoordinatesResponse SendPresetAttackToCoordinatesResponseStructure
    | RequestReportListResponse RequestReportListResponseStructure


type alias RootInformationStructure =
    { location : String
    , tribalWars2 : Maybe TribalWars2RootInformation
    }


type alias TribalWars2RootInformation =
    { readyVillages : List Int
    , selectedVillageId : Int
    , getTotalVillagesResult : Int
    }


type alias ReadSelectedCharacterVillageDetailsResponseStructure =
    { villageId : Int
    , villageDetails : VillageDetails
    }


type alias VillagesByCoordinatesResponseStructure =
    { argument : List VillageByCoordinatesResponseStructure
    , villagesData : List { villageCoordinates : VillageCoordinates, villageData : VillageByCoordinatesResult }
    }


type alias VillageByCoordinatesResponseStructure =
    { villageCoordinates : VillageCoordinates
    , jumpToVillage : Bool
    }


type alias RequestReportListResponseStructure =
    { argument :
        { offset : Int
        , count : Int
        }
    , reportListData : RequestReportListCallbackDataStructure
    }


type alias RequestReportListCallbackDataStructure =
    { offset : Int
    , total : Int
    , reports : List RequestReportListCallbackDataReportStructure
    }


type alias RequestReportListCallbackDataReportStructure =
    { id : Int
    , time_created : Int
    , result : BattleReportResult
    }


type BattleReportResult
    = BattleReportResult_NO_CASUALTIES
    | BattleReportResult_CASUALTIES
    | BattleReportResult_DEFEAT


type alias SendPresetAttackToCoordinatesResponseStructure =
    { villageCoordinates : VillageCoordinates
    }


type alias VillageDetails =
    { coordinates : VillageCoordinates
    , name : String
    , units : Dict.Dict String VillageUnitCount
    , commands : VillageCommands
    }


type alias VillageUnitCount =
    { available : Int }


type alias VillageCommands =
    { outgoing : List VillageCommand
    , incoming : List {}
    }


type alias VillageCommand =
    { time_start : Int
    , time_completed : Int
    , targetVillageId : Maybe Int
    , targetX : Maybe Int
    , targetY : Maybe Int
    , returning : Maybe Bool
    }


type VillageByCoordinatesResult
    = NoVillageThere
    | VillageThere VillageByCoordinatesDetails


type alias VillageByCoordinatesDetails =
    { villageId : Int
    , affiliation : Maybe VillageByCoordinatesAffiliation
    , points : Maybe Int
    , characterName : Maybe String
    }


type VillageByCoordinatesAffiliation
    = AffiliationBarbarian
    | AffiliationOther


type alias ArmyPreset =
    { id : Int
    , name : String
    , units : Dict.Dict String Int
    , assigned_villages : List Int
    }


type alias VillageCoordinates =
    { x : Int
    , y : Int
    }


type InFarmCycleResponse
    = ContinueFarmCycle ContinueFarmCycleStructure
    | FinishFarmCycle { villagesResults : Dict.Dict Int VillageCompletedStructure }


type alias ContinueFarmCycleStructure =
    Maybe ContinueFarmCycleActivity


type ContinueFarmCycleActivity
    = RequestToPage RequestToPageStructure
    | RestartWebBrowser


type RequestToPageStructure
    = ReadRootInformationRequest
    | ReadSelectedCharacterVillageDetailsRequest { villageId : Int }
    | ReadArmyPresets
    | VillagesByCoordinatesRequest (List { coordinates : VillageCoordinates, jumpToVillage : Bool })
    | SendPresetAttackToCoordinatesRequest { coordinates : VillageCoordinates, presetId : Int }
    | VillageMenuActivateVillageRequest
    | ReadBattleReportListRequest


type VillageCompletedStructure
    = NoMatchingArmyPresetEnabledForThisVillage
    | NotEnoughUnits
    | ExhaustedAttackLimit
    | AllFarmsInSearchedAreaAlreadyAttackedInThisCycle
    | VillageDisabledInSettings


type VillageEndDecisionPathStructure
    = CompletedThisVillage VillageCompletedStructure
    | ContinueWithThisVillage { remainingCapacityCommands : Int } ActionFromVillage


type ActionFromVillage
    = GetVillageInfoAtCoordinates VillageCoordinates
    | AttackAtCoordinates ArmyPreset VillageCoordinates


type alias IntervalInt =
    { minimum : Int, maximum : Int }


initState : BotState
initState =
    { timeInMilliseconds = 0
    , settings = initBotSettings
    , currentActivity = Nothing
    , lastRequestToPageId = 0
    , pendingRequestToPageRequestId = Nothing
    , lastRunJavascriptResult = Nothing
    , lastPageLocation = Nothing
    , gameLastPageLocation = Nothing
    , gameRootInformationResult = Nothing
    , ownVillagesDetails = Dict.empty
    , lastJumpToCoordinates = Nothing
    , coordinatesLastCheck = Dict.empty
    , numberOfReadsFromCoordinates = 0
    , readFromGameConsecutiveTimeoutsCount = 0
    , farmState = InFarmCycle { beginTime = 0 } initFarmCycle
    , lastAttackTimeInMilliseconds = Nothing
    , lastActivatedVillageTimeInMilliseconds = Nothing
    , lastStartWebBrowserTimeInSeconds = Nothing
    , startWebBrowserCount = 0
    , completedFarmCycles = []
    , lastRequestReportListResult = Nothing
    , parseResponseError = Nothing
    , cache_relativeCoordinatesToSearchForFarmsPartitions = []
    }


reasonToRestartGameClientFromBotState : BotState -> Maybe String
reasonToRestartGameClientFromBotState state =
    case state.lastStartWebBrowserTimeInSeconds of
        Nothing ->
            Just "Did not yet start the web browser."

        Just lastStartWebBrowserTimeInSeconds ->
            let
                continueAfterCheckLastRunJs =
                    if restartGameClientInterval < (state.timeInMilliseconds // 1000) - lastStartWebBrowserTimeInSeconds then
                        Just ("Last restart was more than " ++ (restartGameClientInterval |> String.fromInt) ++ " seconds ago.")

                    else if readFromGameTimeoutCountThresholdToRestart < state.readFromGameConsecutiveTimeoutsCount then
                        Just ("Reading from game timed out consecutively more than " ++ (readFromGameTimeoutCountThresholdToRestart |> String.fromInt) ++ " times.")

                    else
                        Nothing
            in
            case state.lastRunJavascriptResult of
                Just lastRunJavascriptResult ->
                    if lastRunJavascriptResult.response.webBrowserAvailable then
                        continueAfterCheckLastRunJs

                    else
                        Just "Last request to run javascript returned no browser instance available."

                Nothing ->
                    continueAfterCheckLastRunJs


initFarmCycle : FarmCycleState
initFarmCycle =
    { getArmyPresetsResult = Nothing
    , sentAttackByCoordinates = Dict.empty
    }


botMain : InterfaceToHost.BotConfig State
botMain =
    BotFramework.webBrowserBotMain
        { init = initState
        , processEvent = processWebBrowserBotEvent
        }


processWebBrowserBotEvent : BotEvent -> BotFramework.GenericBotState -> BotState -> { newState : BotState, response : BotResponse, statusMessage : String }
processWebBrowserBotEvent event genericBotState stateBeforeIntegrateEvent =
    case stateBeforeIntegrateEvent |> integrateWebBrowserBotEvent event of
        Err integrateEventError ->
            { newState = stateBeforeIntegrateEvent
            , response = BotFramework.FinishSession
            , statusMessage = "Error: " ++ integrateEventError
            }

        Ok stateBefore ->
            let
                maybeCurrentActivityToWaitFor : Maybe { decisionTree : DecisionPathNode InFarmCycleResponse, activityType : String }
                maybeCurrentActivityToWaitFor =
                    case stateBefore.currentActivity of
                        Nothing ->
                            Nothing

                        Just currentActivity ->
                            let
                                pendingRequestTimeInMilliseconds =
                                    case stateBefore.lastRunJavascriptResult of
                                        Nothing ->
                                            Just currentActivity.beginTimeInMilliseconds

                                        Just lastRunJavascriptResult ->
                                            if currentActivity.beginTimeInMilliseconds <= lastRunJavascriptResult.timeInMilliseconds then
                                                Nothing

                                            else
                                                Just currentActivity.beginTimeInMilliseconds

                                waitTimeAfterLastRunJavascriptResult =
                                    if stateBefore.pendingRequestToPageRequestId == Nothing then
                                        300

                                    else
                                        3000

                                waitTimeLimits =
                                    [ ( "lastRunJavascriptResult"
                                      , stateBefore.lastRunJavascriptResult
                                            |> Maybe.map (.timeInMilliseconds >> (+) waitTimeAfterLastRunJavascriptResult)
                                      )
                                    , ( "pending request"
                                      , pendingRequestTimeInMilliseconds |> Maybe.map ((+) 3000)
                                      )
                                    ]
                                        |> List.filterMap
                                            (\( activityType, maybeWaitTimeLimit ) ->
                                                maybeWaitTimeLimit
                                                    |> Maybe.map (\waitTimeLimit -> ( activityType, waitTimeLimit ))
                                            )

                                effectiveWaitTimeLimits =
                                    waitTimeLimits
                                        |> List.filter (\( _, waitTimeLimit ) -> stateBefore.timeInMilliseconds < waitTimeLimit)
                            in
                            case effectiveWaitTimeLimits |> List.head of
                                Just ( activityType, _ ) ->
                                    -- TODO: Forward the time we want to get notified to the framework, based on the remaining time to the limit.
                                    Just { decisionTree = currentActivity.decision, activityType = activityType }

                                Nothing ->
                                    Nothing
            in
            let
                ( activityDecision, maybeUpdatedState ) =
                    case maybeCurrentActivityToWaitFor of
                        Just currentActivityToWaitFor ->
                            ( currentActivityToWaitFor.decisionTree
                                |> continueDecisionTree
                                    (always (endDecisionPath (BotFramework.ContinueSession Nothing)))
                            , Nothing
                            )

                        Nothing ->
                            let
                                ( botResponse, botState ) =
                                    decideNextAction
                                        { lastPageLocation = stateBeforeIntegrateEvent.lastPageLocation
                                        , gameLastPageLocation = stateBeforeIntegrateEvent.gameLastPageLocation
                                        , webBrowserRunning = genericBotState.webBrowserRunning
                                        }
                                        { stateBefore | currentActivity = Nothing }

                                lastPageLocation =
                                    case botResponse |> Common.DecisionTree.unpackToDecisionStagesDescriptionsAndLeaf |> Tuple.second of
                                        BotFramework.ContinueSession (Just (BotFramework.StartWebBrowser startWebBrowser)) ->
                                            startWebBrowser.pageGoToUrl

                                        BotFramework.ContinueSession (Just (BotFramework.CloseWebBrowser _)) ->
                                            Nothing

                                        _ ->
                                            botState.lastPageLocation
                            in
                            ( botResponse, Just { botState | lastPageLocation = lastPageLocation } )

                ( activityDecisionStages, responseToFramework ) =
                    activityDecision
                        |> unpackToDecisionStagesDescriptionsAndLeaf

                newState =
                    maybeUpdatedState |> Maybe.withDefault stateBefore
            in
            { newState = newState
            , response = responseToFramework
            , statusMessage = statusMessageFromState newState { activityDecisionStages = activityDecisionStages }
            }


decideNextAction :
    { lastPageLocation : Maybe String, gameLastPageLocation : Maybe String, webBrowserRunning : Bool }
    -> BotState
    -> ( DecisionPathNode BotResponse, BotState )
decideNextAction { lastPageLocation, gameLastPageLocation, webBrowserRunning } stateBefore =
    case stateBefore.farmState of
        InBreak farmBreak ->
            let
                minutesSinceLastFarmCycleCompletion =
                    (stateBefore.timeInMilliseconds // 1000 - farmBreak.lastCycleCompletionTime) // 60

                minutesToNextFarmCycleStart =
                    (farmBreak.nextCycleStartTime - stateBefore.timeInMilliseconds // 1000) // 60
            in
            if minutesToNextFarmCycleStart < 1 then
                ( describeBranch "Start next farm cycle."
                    (endDecisionPath (BotFramework.ContinueSession Nothing))
                , { stateBefore | farmState = InFarmCycle { beginTime = stateBefore.timeInMilliseconds // 1000 } initFarmCycle }
                )

            else
                let
                    botRequest =
                        if
                            (stateBefore.settings.closeGameClientDuringBreak == AppSettings.Yes)
                                && (stateBefore.gameLastPageLocation == stateBefore.lastPageLocation)
                        then
                            Just
                                (BotFramework.StartWebBrowser
                                    { userProfileId = stateBefore.settings.webBrowserUserProfileId
                                    , pageGoToUrl = Just "about:blank"
                                    }
                                )

                        else
                            Nothing
                in
                ( describeBranch
                    ("Next farm cycle starts in "
                        ++ (minutesToNextFarmCycleStart |> String.fromInt)
                        ++ " minutes. Last cycle completed "
                        ++ (minutesSinceLastFarmCycleCompletion |> String.fromInt)
                        ++ " minutes ago."
                    )
                    (endDecisionPath (BotFramework.ContinueSession botRequest))
                , stateBefore
                )

        InFarmCycle farmCycleBegin farmCycleState ->
            let
                decisionInFarmCycle =
                    decideInFarmCycle stateBefore farmCycleState

                ( _, decisionInFarmCycleLeaf ) =
                    unpackToDecisionStagesDescriptionsAndLeaf decisionInFarmCycle

                ( newLeaf, maybeActivityInFarmCycle, updatedStateInFarmCycle ) =
                    case decisionInFarmCycleLeaf of
                        ContinueFarmCycle continueFarmCycleActivity ->
                            let
                                ( maybeRequest, updatedStateFromContinueCycle ) =
                                    case continueFarmCycleActivity of
                                        Nothing ->
                                            ( Nothing, stateBefore )

                                        Just activity ->
                                            let
                                                continueWithStartWebBrowser =
                                                    ( BotFramework.StartWebBrowser
                                                        { pageGoToUrl =
                                                            [ gameLastPageLocation, stateBefore.settings.openWebsiteOnStart ]
                                                                |> List.filterMap identity
                                                                |> List.head
                                                        , userProfileId = stateBefore.settings.webBrowserUserProfileId
                                                        }
                                                    , { stateBefore
                                                        | lastStartWebBrowserTimeInSeconds = Just (stateBefore.timeInMilliseconds // 1000)
                                                        , startWebBrowserCount = stateBefore.startWebBrowserCount + 1
                                                        , readFromGameConsecutiveTimeoutsCount = 0
                                                      }
                                                    )

                                                ( requestToFramework, updatedStateForActivity ) =
                                                    case activity of
                                                        RequestToPage requestToPage ->
                                                            if
                                                                not webBrowserRunning
                                                                    || ((stateBefore.lastPageLocation /= stateBefore.gameLastPageLocation)
                                                                            && (stateBefore.gameLastPageLocation /= Nothing)
                                                                       )
                                                            then
                                                                continueWithStartWebBrowser

                                                            else
                                                                let
                                                                    requestComponents =
                                                                        componentsForRequestToPage requestToPage

                                                                    requestToPageId =
                                                                        stateBefore.lastRequestToPageId + 1

                                                                    requestToPageIdString =
                                                                        requestToPageId |> String.fromInt
                                                                in
                                                                ( BotFramework.RunJavascriptInCurrentPageRequest
                                                                    { javascript = requestComponents.javascript
                                                                    , requestId = requestToPageIdString
                                                                    , timeToWaitForCallbackMilliseconds =
                                                                        case requestComponents.waitForCallbackDuration of
                                                                            Just waitForCallbackDuration ->
                                                                                waitForCallbackDuration

                                                                            Nothing ->
                                                                                0
                                                                    }
                                                                , { stateBefore
                                                                    | lastRequestToPageId = requestToPageId
                                                                    , pendingRequestToPageRequestId = Just requestToPageIdString
                                                                  }
                                                                )

                                                        RestartWebBrowser ->
                                                            continueWithStartWebBrowser
                                            in
                                            ( Just requestToFramework
                                            , updatedStateForActivity
                                            )
                            in
                            ( endDecisionPath (BotFramework.ContinueSession maybeRequest)
                            , Just decisionInFarmCycle
                            , updatedStateFromContinueCycle
                            )

                        FinishFarmCycle { villagesResults } ->
                            let
                                completedFarmCycles =
                                    { beginTime = farmCycleBegin.beginTime
                                    , completionTime = stateBefore.timeInMilliseconds // 1000
                                    , attacksCount = farmCycleState.sentAttackByCoordinates |> Dict.size
                                    , villagesResults = villagesResults
                                    }
                                        :: stateBefore.completedFarmCycles

                                currentTimeInSeconds =
                                    stateBefore.timeInMilliseconds // 1000

                                breakLengthRange =
                                    (stateBefore.settings.breakDurationMinutes.maximum
                                        - stateBefore.settings.breakDurationMinutes.minimum
                                    )
                                        * 60

                                breakLengthRandomComponent =
                                    if breakLengthRange == 0 then
                                        0

                                    else
                                        stateBefore.timeInMilliseconds |> modBy breakLengthRange

                                breakLength =
                                    (stateBefore.settings.breakDurationMinutes.minimum * 60)
                                        + breakLengthRandomComponent

                                nextCycleStartTime =
                                    currentTimeInSeconds + breakLength

                                farmState =
                                    InBreak
                                        { lastCycleCompletionTime = currentTimeInSeconds
                                        , nextCycleStartTime = nextCycleStartTime
                                        }

                                stateAfterFinishingFarmCycle =
                                    { stateBefore
                                        | farmState = farmState
                                        , completedFarmCycles = completedFarmCycles
                                    }
                            in
                            ( describeBranch "Finish farm cycle."
                                (if stateBefore.settings.numberOfFarmCycles <= (stateAfterFinishingFarmCycle.completedFarmCycles |> List.length) then
                                    describeBranch
                                        ("Finish session because I finished all " ++ (stateAfterFinishingFarmCycle.completedFarmCycles |> List.length |> String.fromInt) ++ " configured farm cycles.")
                                        (endDecisionPath BotFramework.FinishSession)

                                 else
                                    describeBranch "Enter break."
                                        (endDecisionPath (BotFramework.ContinueSession Nothing))
                                )
                            , Nothing
                            , stateAfterFinishingFarmCycle
                            )

                currentActivity =
                    maybeActivityInFarmCycle
                        |> Maybe.map
                            (\activityInFarmCycle ->
                                { decision = activityInFarmCycle, beginTimeInMilliseconds = stateBefore.timeInMilliseconds }
                            )
            in
            ( decisionInFarmCycle
                |> continueDecisionTree (always newLeaf)
            , { updatedStateInFarmCycle | currentActivity = currentActivity }
            )


parseBotSettingBreakDurationMinutes : String -> Result String (BotSettings -> BotSettings)
parseBotSettingBreakDurationMinutes =
    parseIntervalIntFromPointOrIntervalString
        >> Result.map (\interval -> \settings -> { settings | breakDurationMinutes = interval })


parseBotSettingLimitOutgoingCommandsPerVillage : String -> Result String (BotSettings -> BotSettings)
parseBotSettingLimitOutgoingCommandsPerVillage =
    parseIntervalIntFromPointOrIntervalString
        >> Result.map (\interval -> \settings -> { settings | limitOutgoingCommandsPerVillage = interval })


parseIntervalIntFromPointOrIntervalString : String -> Result String IntervalInt
parseIntervalIntFromPointOrIntervalString intervalAsString =
    let
        boundsParseResults =
            intervalAsString
                |> String.split "-"
                |> List.map (\boundString -> boundString |> String.trim |> String.toInt |> Result.fromMaybe ("Failed to parse '" ++ boundString ++ "'"))
    in
    boundsParseResults
        |> Result.Extra.combine
        |> Result.andThen
            (\bounds ->
                case ( bounds |> List.minimum, bounds |> List.maximum ) of
                    ( Just minimum, Just maximum ) ->
                        Ok { minimum = minimum, maximum = maximum }

                    _ ->
                        Err "Missing value"
            )


parseSettingFarmAvoidCoordinates : String -> Result String (BotSettings -> BotSettings)
parseSettingFarmAvoidCoordinates listOfCoordinatesAsString =
    listOfCoordinatesAsString
        |> parseSettingListCoordinates
        |> Result.map
            (\farmAvoidCoordinates ->
                \settings -> { settings | farmAvoidCoordinates = settings.farmAvoidCoordinates ++ farmAvoidCoordinates }
            )


parseSettingListCoordinates : String -> Result String (List VillageCoordinates)
parseSettingListCoordinates listOfCoordinatesAsString =
    let
        coordinatesParseResults : List (Result String VillageCoordinates)
        coordinatesParseResults =
            listOfCoordinatesAsString
                |> String.split " "
                |> List.filter (String.isEmpty >> not)
                |> List.map
                    (\coordinatesAsString ->
                        (case coordinatesAsString |> String.split "|" |> List.map String.trim of
                            [ xAsString, yAsString ] ->
                                case ( xAsString |> String.toInt, yAsString |> String.toInt ) of
                                    ( Just x, Just y ) ->
                                        Ok { x = x, y = y }

                                    _ ->
                                        Err "Failed to parse component as integer."

                            _ ->
                                Err "Unexpected number of components."
                        )
                            |> Result.mapError
                                (\errorInCoordinate ->
                                    "Failed to parse coordinates string '" ++ coordinatesAsString ++ "': " ++ errorInCoordinate
                                )
                    )
    in
    coordinatesParseResults
        |> Result.Extra.combine


integrateWebBrowserBotEvent : BotEvent -> BotState -> Result String BotState
integrateWebBrowserBotEvent event stateBefore =
    case event of
        BotFramework.SetBotSettings settingsString ->
            let
                parseSettingsResult =
                    parseBotSettings settingsString
            in
            parseSettingsResult
                |> Result.map
                    (\newSettings ->
                        { stateBefore
                            | settings = newSettings
                            , cache_relativeCoordinatesToSearchForFarmsPartitions =
                                relativeCoordinatesToSearchForFarmsPartitions newSettings
                        }
                    )
                |> Result.mapError (\parseError -> "Failed to parse these bot-settings: " ++ parseError)

        BotFramework.ArrivedAtTime { timeInMilliseconds } ->
            Ok { stateBefore | timeInMilliseconds = timeInMilliseconds }

        BotFramework.RunJavascriptInCurrentPageResponse runJavascriptInCurrentPageResponse ->
            Ok
                (integrateWebBrowserBotEventRunJavascriptInCurrentPageResponse runJavascriptInCurrentPageResponse stateBefore)


integrateWebBrowserBotEventRunJavascriptInCurrentPageResponse : BotFramework.RunJavascriptInCurrentPageResponseStructure -> BotState -> BotState
integrateWebBrowserBotEventRunJavascriptInCurrentPageResponse runJavascriptInCurrentPageResponse stateBefore =
    let
        pendingRequestToPageRequestId =
            if Just runJavascriptInCurrentPageResponse.requestId == stateBefore.pendingRequestToPageRequestId then
                Nothing

            else
                stateBefore.pendingRequestToPageRequestId

        parseAsRootInfoResult =
            runJavascriptInCurrentPageResponse.directReturnValueAsString
                |> Json.Decode.decodeString decodeRootInformation

        lastPageLocation =
            case parseAsRootInfoResult of
                Ok parseAsRootInfoSuccess ->
                    Just parseAsRootInfoSuccess.location

                _ ->
                    stateBefore.lastPageLocation

        gameLastPageLocation =
            if
                Maybe.withDefault False (Maybe.map (stringContainsIgnoringCase "tribalwars2.com/game.php") lastPageLocation)
                    && (Maybe.andThen .tribalWars2 (Result.toMaybe parseAsRootInfoResult) /= Nothing)
            then
                lastPageLocation

            else
                stateBefore.gameLastPageLocation

        stateAfterIntegrateResponse =
            { stateBefore
                | pendingRequestToPageRequestId = pendingRequestToPageRequestId
                , lastRunJavascriptResult =
                    Just
                        { timeInMilliseconds = stateBefore.timeInMilliseconds
                        , response = runJavascriptInCurrentPageResponse
                        , parseResult = parseAsRootInfoResult
                        }
                , lastPageLocation = lastPageLocation
                , gameLastPageLocation = gameLastPageLocation
            }

        parseResult =
            runJavascriptInCurrentPageResponse.directReturnValueAsString
                |> Json.Decode.decodeString decodeResponseFromBrowser
    in
    case parseResult of
        Err error ->
            { stateAfterIntegrateResponse | parseResponseError = Just error }

        Ok parseSuccess ->
            let
                stateAfterParseSuccess =
                    { stateAfterIntegrateResponse | parseResponseError = Nothing }
            in
            case parseSuccess of
                RootInformation rootInformation ->
                    case rootInformation.tribalWars2 of
                        Nothing ->
                            stateAfterIntegrateResponse

                        Just gameRootInformation ->
                            { stateAfterParseSuccess
                                | gameRootInformationResult =
                                    Just
                                        { timeInMilliseconds = stateBefore.timeInMilliseconds
                                        , gameRootInformation = gameRootInformation
                                        }
                            }

                ReadSelectedCharacterVillageDetailsResponse readVillageDetailsResponse ->
                    { stateAfterParseSuccess
                        | ownVillagesDetails =
                            stateAfterParseSuccess.ownVillagesDetails
                                |> Dict.insert readVillageDetailsResponse.villageId
                                    { timeInMilliseconds = stateBefore.timeInMilliseconds, villageDetails = readVillageDetailsResponse.villageDetails }
                    }

                VillagesByCoordinatesResponse villagesByCoordinatesResponse ->
                    let
                        maybeCoordinatesJumpedTo =
                            villagesByCoordinatesResponse.argument
                                |> List.filter .jumpToVillage
                                |> List.head
                                |> Maybe.map .villageCoordinates

                        stateAfterRememberJump =
                            case maybeCoordinatesJumpedTo of
                                Just coordinatesJumpedTo ->
                                    { stateAfterParseSuccess
                                        | lastJumpToCoordinates =
                                            Just
                                                { timeInMilliseconds = stateBefore.timeInMilliseconds
                                                , coordinates = coordinatesJumpedTo
                                                }
                                    }

                                Nothing ->
                                    stateAfterParseSuccess
                    in
                    villagesByCoordinatesResponse.villagesData
                        |> List.foldl
                            (\villageByCoordinates intermediateState ->
                                { intermediateState
                                    | coordinatesLastCheck =
                                        intermediateState.coordinatesLastCheck
                                            |> Dict.insert
                                                ( villageByCoordinates.villageCoordinates.x, villageByCoordinates.villageCoordinates.y )
                                                { timeInMilliseconds = intermediateState.timeInMilliseconds
                                                , result = villageByCoordinates.villageData
                                                }
                                    , numberOfReadsFromCoordinates = intermediateState.numberOfReadsFromCoordinates + 1
                                    , readFromGameConsecutiveTimeoutsCount = 0
                                }
                            )
                            stateAfterRememberJump

                SendPresetAttackToCoordinatesResponse sendPresetAttackToCoordinatesResponse ->
                    let
                        updatedFarmState =
                            case stateAfterParseSuccess.farmState of
                                InFarmCycle farmCycleBegin currentFarmCycleBefore ->
                                    let
                                        sentAttackByCoordinates =
                                            currentFarmCycleBefore.sentAttackByCoordinates
                                                |> Dict.insert
                                                    ( sendPresetAttackToCoordinatesResponse.villageCoordinates.x
                                                    , sendPresetAttackToCoordinatesResponse.villageCoordinates.y
                                                    )
                                                    ()
                                    in
                                    Just
                                        (InFarmCycle farmCycleBegin
                                            { currentFarmCycleBefore | sentAttackByCoordinates = sentAttackByCoordinates }
                                        )

                                InBreak _ ->
                                    Nothing
                    in
                    { stateAfterParseSuccess
                        | farmState = updatedFarmState |> Maybe.withDefault stateAfterParseSuccess.farmState
                        , lastAttackTimeInMilliseconds = Just stateBefore.timeInMilliseconds
                    }

                GetPresetsResponse armyPresets ->
                    let
                        farmState =
                            case stateBefore.farmState of
                                InBreak _ ->
                                    stateBefore.farmState

                                InFarmCycle cycleBeginTime inFarmCycle ->
                                    InFarmCycle cycleBeginTime
                                        { inFarmCycle | getArmyPresetsResult = Just armyPresets }
                    in
                    { stateBefore | farmState = farmState }

                ActivatedVillageResponse ->
                    { stateBefore | lastActivatedVillageTimeInMilliseconds = Just stateBefore.timeInMilliseconds }

                RequestReportListResponse requestReportList ->
                    { stateBefore | lastRequestReportListResult = Just requestReportList }


maintainGameClient : BotState -> Maybe (DecisionPathNode InFarmCycleResponse)
maintainGameClient botState =
    case
        botState
            |> lastStartWebBrowserAgeInSecondsFromState
            |> Maybe.andThen (nothingFromIntIfGreaterThan waitDurationAfterReloadWebPage)
    of
        Just lastReloadPageAgeInSeconds ->
            describeBranch
                ("Waiting because reloaded web page " ++ (lastReloadPageAgeInSeconds |> String.fromInt) ++ " seconds ago.")
                (endDecisionPath (ContinueFarmCycle Nothing))
                |> Just

        Nothing ->
            case botState |> reasonToRestartGameClientFromBotState of
                Just reasonToRestartGameClient ->
                    describeBranch
                        ("Restart the game client (" ++ reasonToRestartGameClient ++ ").")
                        (endDecisionPath (ContinueFarmCycle (Just RestartWebBrowser)))
                        |> Just

                Nothing ->
                    case botState.lastRunJavascriptResult of
                        Nothing ->
                            describeBranch
                                "Test if web browser is already open."
                                (endDecisionPath (ContinueFarmCycle (Just (RequestToPage ReadRootInformationRequest))))
                                |> Just

                        Just _ ->
                            Nothing


decideInFarmCycle : BotState -> FarmCycleState -> DecisionPathNode InFarmCycleResponse
decideInFarmCycle botState farmCycleState =
    maintainGameClient botState
        |> Maybe.withDefault (decideInFarmCycleWhenNotWaitingGlobally botState farmCycleState)


decideInFarmCycleWhenNotWaitingGlobally : BotState -> FarmCycleState -> DecisionPathNode InFarmCycleResponse
decideInFarmCycleWhenNotWaitingGlobally botState farmCycleState =
    let
        sufficientlyNewGameRootInformation =
            botState.gameRootInformationResult
                |> Result.fromMaybe "did not receive any yet"
                |> Result.andThen
                    (\gameRootInformationResult ->
                        let
                            updateTimeMinimumMilli =
                                (botState.lastActivatedVillageTimeInMilliseconds |> Maybe.withDefault 0)
                                    |> max (botState.timeInMilliseconds - gameRootInformationQueryInterval * 1000)
                        in
                        if gameRootInformationResult.timeInMilliseconds <= updateTimeMinimumMilli then
                            Err "last received is not recent enough"

                        else if areAllVillagesLoaded gameRootInformationResult.gameRootInformation then
                            Ok gameRootInformationResult.gameRootInformation

                        else
                            Err
                                "last received has not all villages loaded yet"
                    )
    in
    case sufficientlyNewGameRootInformation of
        Err error ->
            describeBranch ("Read game root info (" ++ error ++ ")")
                (endDecisionPath (ContinueFarmCycle (Just (RequestToPage ReadRootInformationRequest))))

        Ok gameRootInformation ->
            decideInFarmCycleWithGameRootInformation botState farmCycleState gameRootInformation


decideInFarmCycleWithGameRootInformation : BotState -> FarmCycleState -> TribalWars2RootInformation -> DecisionPathNode InFarmCycleResponse
decideInFarmCycleWithGameRootInformation botState farmCycleState gameRootInformation =
    let
        ownVillageUpdateTimeMinimumMilli =
            botState.timeInMilliseconds - (ownVillageInfoMaxAge * 1000)

        sufficientyFreshOwnVillagesDetails =
            botState.ownVillagesDetails
                |> Dict.filter (\_ response -> ownVillageUpdateTimeMinimumMilli < response.timeInMilliseconds)

        ownVillagesNeedingDetailsUpdate =
            gameRootInformation.readyVillages
                |> List.filter (\villageId -> sufficientyFreshOwnVillagesDetails |> Dict.member villageId |> not)

        selectedVillageUpdateTimeMinimumMilli =
            (botState.lastAttackTimeInMilliseconds |> Maybe.withDefault 0)
                |> max (botState.timeInMilliseconds - (selectedVillageInfoMaxAge * 1000))

        selectedVillageUpdatedDetails =
            sufficientyFreshOwnVillagesDetails
                |> Dict.get gameRootInformation.selectedVillageId
                |> Maybe.andThen
                    (\selectedVillageDetailsResponse ->
                        if selectedVillageDetailsResponse.timeInMilliseconds <= selectedVillageUpdateTimeMinimumMilli then
                            Nothing

                        else
                            Just selectedVillageDetailsResponse.villageDetails
                    )

        describeSelectedVillageDetails =
            botState.ownVillagesDetails
                |> Dict.get gameRootInformation.selectedVillageId
                |> Maybe.map
                    (\villageDetailsResponse ->
                        let
                            sumOfAvailableUnits =
                                villageDetailsResponse.villageDetails.units
                                    |> Dict.values
                                    |> List.map .available
                                    |> List.sum

                            lastUpdateAge =
                                (botState.timeInMilliseconds - villageDetailsResponse.timeInMilliseconds)
                                    // 1000

                            outgoingCommandsCount =
                                villageDetailsResponse.villageDetails.commands.outgoing |> List.length
                        in
                        [ (villageDetailsResponse.villageDetails.coordinates |> villageCoordinatesDisplayText)
                            ++ " '"
                            ++ villageDetailsResponse.villageDetails.name
                            ++ "'."
                        , "Last update " ++ (lastUpdateAge |> String.fromInt) ++ " s ago."
                        , (sumOfAvailableUnits |> String.fromInt) ++ " available units."
                        , (outgoingCommandsCount |> String.fromInt) ++ " outgoing commands."
                        ]
                            |> String.join " "
                    )
                |> Maybe.withDefault "No details yet for this village."

        describeSelectedVillage =
            "Currently selected village is "
                ++ (gameRootInformation.selectedVillageId |> String.fromInt)
                ++ " ("
                ++ describeSelectedVillageDetails
                ++ ")"

        continueFromDecisionInVillage : VillageEndDecisionPathStructure -> DecisionPathNode InFarmCycleResponse
        continueFromDecisionInVillage decisionInVillage =
            case decisionInVillage of
                ContinueWithThisVillage _ (GetVillageInfoAtCoordinates coordinates) ->
                    describeBranch
                        ("Search for village at " ++ (coordinates |> villageCoordinatesDisplayText) ++ ".")
                        (endDecisionPath
                            (ContinueFarmCycle
                                (Just
                                    (RequestToPage
                                        (requestToPageStructureToReadMapChunkContainingCoordinates coordinates)
                                    )
                                )
                            )
                        )

                ContinueWithThisVillage _ (AttackAtCoordinates armyPreset coordinates) ->
                    describeBranch
                        ("Farm at " ++ (coordinates |> villageCoordinatesDisplayText) ++ ".")
                        (case requestToJumpToVillageIfNotYetDone botState coordinates of
                            Just jumpToVillageRequest ->
                                describeBranch
                                    ("Jump to village at " ++ (coordinates |> villageCoordinatesDisplayText) ++ ".")
                                    (endDecisionPath (ContinueFarmCycle (Just (RequestToPage jumpToVillageRequest))))

                            Nothing ->
                                describeBranch
                                    ("Send attack using preset '" ++ armyPreset.name ++ "'.")
                                    (endDecisionPath
                                        (ContinueFarmCycle
                                            (Just
                                                (RequestToPage
                                                    (SendPresetAttackToCoordinatesRequest { coordinates = coordinates, presetId = armyPreset.id })
                                                )
                                            )
                                        )
                                    )
                        )

                CompletedThisVillage currentVillageCompletion ->
                    describeBranch
                        ("Current village is completed ("
                            ++ (describeVillageCompletion currentVillageCompletion).decisionBranch
                            ++ ")."
                        )
                        (let
                            otherVillagesWithDetails =
                                gameRootInformation.readyVillages
                                    |> List.filterMap
                                        (\otherVillageId ->
                                            sufficientyFreshOwnVillagesDetails
                                                |> Dict.get otherVillageId
                                                |> Maybe.map
                                                    (\otherVillageDetailsResponse ->
                                                        ( otherVillageId, otherVillageDetailsResponse.villageDetails )
                                                    )
                                        )
                                    |> Dict.fromList
                                    |> Dict.remove gameRootInformation.selectedVillageId

                            otherVillagesDetailsAndDecisions =
                                otherVillagesWithDetails
                                    |> Dict.map
                                        (\otherVillageId otherVillageDetails ->
                                            ( otherVillageDetails
                                            , decideNextActionForVillage botState farmCycleState ( otherVillageId, otherVillageDetails )
                                            )
                                        )

                            otherVillagesWithAvailableAction =
                                otherVillagesDetailsAndDecisions
                                    |> Dict.toList
                                    |> List.filter
                                        (\( _, ( _, otherVillageDecisionPath ) ) ->
                                            case otherVillageDecisionPath |> unpackToDecisionStagesDescriptionsAndLeaf |> Tuple.second of
                                                CompletedThisVillage _ ->
                                                    False

                                                ContinueWithThisVillage conditions _ ->
                                                    switchToOtherVillageCommandCapacityMinimum <= conditions.remainingCapacityCommands
                                        )
                         in
                         case otherVillagesWithAvailableAction |> List.head of
                            Nothing ->
                                let
                                    villagesResults =
                                        otherVillagesDetailsAndDecisions
                                            |> Dict.map (always Tuple.second)
                                            |> Dict.toList
                                            |> List.filterMap
                                                (\( otherVillageId, otherVillageDecisionPath ) ->
                                                    case otherVillageDecisionPath |> unpackToDecisionStagesDescriptionsAndLeaf |> Tuple.second of
                                                        CompletedThisVillage otherVillageCompletion ->
                                                            Just ( otherVillageId, otherVillageCompletion )

                                                        ContinueWithThisVillage _ _ ->
                                                            Nothing
                                                )
                                            |> Dict.fromList
                                            |> Dict.insert gameRootInformation.selectedVillageId currentVillageCompletion
                                in
                                describeBranch "All villages completed."
                                    (endDecisionPath (FinishFarmCycle { villagesResults = villagesResults }))

                            Just ( villageToActivateId, ( villageToActivateDetails, _ ) ) ->
                                describeBranch
                                    ("Switch to village " ++ (villageToActivateId |> String.fromInt) ++ " at " ++ (villageToActivateDetails.coordinates |> villageCoordinatesDisplayText) ++ ".")
                                    (endDecisionPath
                                        (ContinueFarmCycle
                                            (Just
                                                (RequestToPage
                                                    (requestToJumpToVillageIfNotYetDone botState villageToActivateDetails.coordinates
                                                        |> Maybe.withDefault VillageMenuActivateVillageRequest
                                                    )
                                                )
                                            )
                                        )
                                    )
                        )

        readBattleReportList =
            describeBranch "Read report list"
                (endDecisionPath (ContinueFarmCycle (Just (RequestToPage ReadBattleReportListRequest))))
    in
    {-
       Disable reading battle report list for to clean up status message.
          case botState.lastRequestReportListResult of
              Nothing ->
                  readBattleReportList

              Just readReportListResult ->
    -}
    case ownVillagesNeedingDetailsUpdate of
        ownVillageNeedingDetailsUpdate :: _ ->
            describeBranch
                ("Read status of own village " ++ (ownVillageNeedingDetailsUpdate |> String.fromInt) ++ ".")
                (endDecisionPath
                    (ContinueFarmCycle
                        (Just (RequestToPage (ReadSelectedCharacterVillageDetailsRequest { villageId = ownVillageNeedingDetailsUpdate })))
                    )
                )

        [] ->
            describeBranch describeSelectedVillage
                (case selectedVillageUpdatedDetails of
                    Nothing ->
                        describeBranch
                            ("Read status of current selected village (" ++ (gameRootInformation.selectedVillageId |> String.fromInt) ++ ")")
                            (endDecisionPath
                                (ContinueFarmCycle
                                    (Just (RequestToPage (ReadSelectedCharacterVillageDetailsRequest { villageId = gameRootInformation.selectedVillageId })))
                                )
                            )

                    Just selectedVillageDetails ->
                        case farmCycleState.getArmyPresetsResult |> Maybe.withDefault [] of
                            [] ->
                                {- 2020-01-28 Observation: We get an empty list here at least sometimes at the beginning of a session.
                                   The number of presets we get can increase with the next query.

                                   -- TODO: Add timeout for getting presets.
                                -}
                                describeBranch
                                    "Did not find any army presets. Maybe loading is not completed yet."
                                    (describeBranch
                                        "Read army presets."
                                        (endDecisionPath (ContinueFarmCycle (Just (RequestToPage ReadArmyPresets))))
                                    )

                            _ ->
                                decideNextActionForVillage
                                    botState
                                    farmCycleState
                                    ( gameRootInformation.selectedVillageId, selectedVillageDetails )
                                    |> continueDecisionTree continueFromDecisionInVillage
                )


requestToPageStructureToReadMapChunkContainingCoordinates : VillageCoordinates -> RequestToPageStructure
requestToPageStructureToReadMapChunkContainingCoordinates villageCoordinates =
    let
        mapChunkSideLength =
            10

        mapChunkX =
            (villageCoordinates.x // mapChunkSideLength) * mapChunkSideLength

        mapChunkY =
            (villageCoordinates.y // mapChunkSideLength) * mapChunkSideLength

        coordinatesToRead =
            List.range mapChunkX (mapChunkX + mapChunkSideLength - 1)
                |> List.concatMap
                    (\x ->
                        List.range mapChunkY (mapChunkY + mapChunkSideLength - 1)
                            |> List.map (\y -> { x = x, y = y })
                    )
    in
    coordinatesToRead
        |> List.map (\coordinates -> { coordinates = coordinates, jumpToVillage = False })
        |> VillagesByCoordinatesRequest


describeVillageCompletion : VillageCompletedStructure -> { decisionBranch : String, cycleStatsGroup : String }
describeVillageCompletion villageCompletion =
    case villageCompletion of
        NoMatchingArmyPresetEnabledForThisVillage ->
            { decisionBranch = "No matching preset for this village."
            , cycleStatsGroup = "No preset"
            }

        NotEnoughUnits ->
            { decisionBranch = "Not enough units."
            , cycleStatsGroup = "Out of units"
            }

        ExhaustedAttackLimit ->
            { decisionBranch = "Exhausted the attack limit."
            , cycleStatsGroup = "Attack limit"
            }

        AllFarmsInSearchedAreaAlreadyAttackedInThisCycle ->
            { decisionBranch = "All farms in the search area have already been attacked in this farm cycle."
            , cycleStatsGroup = "Out of farms"
            }

        VillageDisabledInSettings ->
            { decisionBranch = "Farming for this village is disabled in the settings."
            , cycleStatsGroup = "Disabled in settings"
            }


lastStartWebBrowserAgeInSecondsFromState : BotState -> Maybe Int
lastStartWebBrowserAgeInSecondsFromState state =
    state.lastStartWebBrowserTimeInSeconds
        |> Maybe.map (\lastStartWebBrowserTimeInSeconds -> state.timeInMilliseconds // 1000 - lastStartWebBrowserTimeInSeconds)


requestToJumpToVillageIfNotYetDone : BotState -> VillageCoordinates -> Maybe RequestToPageStructure
requestToJumpToVillageIfNotYetDone state coordinates =
    let
        needToJumpThere =
            case state.lastJumpToCoordinates of
                Nothing ->
                    True

                Just lastJumpToCoordinates ->
                    lastJumpToCoordinates.coordinates
                        /= coordinates
                        || lastJumpToCoordinates.timeInMilliseconds
                        < state.timeInMilliseconds
                        - 7000
    in
    if needToJumpThere then
        Just (VillagesByCoordinatesRequest [ { coordinates = coordinates, jumpToVillage = True } ])

    else
        Nothing


decideNextActionForVillage :
    BotState
    -> FarmCycleState
    -> ( Int, VillageDetails )
    -> DecisionPathNode VillageEndDecisionPathStructure
decideNextActionForVillage botState farmCycleState ( villageId, villageDetails ) =
    if botState.settings.farmAvoidCoordinates |> List.member villageDetails.coordinates then
        endDecisionPath (CompletedThisVillage VillageDisabledInSettings)

    else
        pickBestMatchingArmyPresetForVillage
            (implicitSettingsFromExplicitSettings botState.settings)
            (farmCycleState.getArmyPresetsResult |> Maybe.withDefault [])
            ( villageId, villageDetails )
            (decideNextActionForVillageAfterChoosingPreset botState farmCycleState ( villageId, villageDetails ))


decideNextActionForVillageAfterChoosingPreset :
    BotState
    -> FarmCycleState
    -> ( Int, VillageDetails )
    -> ArmyPreset
    -> DecisionPathNode VillageEndDecisionPathStructure
decideNextActionForVillageAfterChoosingPreset botState farmCycleState ( villageId, villageDetails ) armyPreset =
    let
        villageInfoCheckFromCoordinates coordinates =
            botState.coordinatesLastCheck |> Dict.get ( coordinates.x, coordinates.y )

        numberOfCommandsFromThisVillage =
            villageDetails.commands.outgoing |> List.length

        limitOutgoingCommandsPerVillageRandomizedAmount =
            botState.settings.limitOutgoingCommandsPerVillage.maximum
                - botState.settings.limitOutgoingCommandsPerVillage.minimum

        limitOutgoingCommandsPerVillageRandomAmount =
            if 0 < limitOutgoingCommandsPerVillageRandomizedAmount then
                botState.timeInMilliseconds |> modBy limitOutgoingCommandsPerVillageRandomizedAmount

            else
                0

        limitOutgoingCommandsPerVillage =
            botState.settings.limitOutgoingCommandsPerVillage.minimum
                + limitOutgoingCommandsPerVillageRandomAmount

        remainingCapacityCommands =
            limitOutgoingCommandsPerVillage - numberOfCommandsFromThisVillage
    in
    if remainingCapacityCommands < 1 then
        describeBranch
            ("Number of commands from this village is " ++ (numberOfCommandsFromThisVillage |> String.fromInt) ++ ".")
            (endDecisionPath (CompletedThisVillage ExhaustedAttackLimit))

    else
        let
            sentAttackToCoordinates coordinates =
                (farmCycleState.sentAttackByCoordinates
                    |> Dict.get ( coordinates.x, coordinates.y )
                )
                    /= Nothing

            firstMatchFromRelativeCoordinates =
                List.map (offsetVillageCoordinates villageDetails.coordinates)
                    >> List.filter
                        (\coordinates ->
                            if sentAttackToCoordinates coordinates then
                                False

                            else
                                case villageInfoCheckFromCoordinates coordinates of
                                    Nothing ->
                                        True

                                    Just coordinatesCheck ->
                                        case coordinatesCheck.result of
                                            NoVillageThere ->
                                                False

                                            VillageThere village ->
                                                villageMatchesSettingsForFarm botState.settings coordinates village
                        )
                    >> List.head

            nextRemainingCoordinates =
                {- 2020-03-15 Specialize for runtime expenses:
                   Adapt to limitations of the current Elm runtime:
                   Process the coordinates in partitions to reduce computations of results we will not use anyway. In the end, we only take the first element, but the current runtime performs a more eager evaluation.
                -}
                botState.cache_relativeCoordinatesToSearchForFarmsPartitions
                    |> List.foldl
                        (\coordinatesPartition result ->
                            if result /= Nothing then
                                result

                            else
                                firstMatchFromRelativeCoordinates coordinatesPartition
                        )
                        Nothing
        in
        nextRemainingCoordinates
            |> Maybe.map
                (\nextCoordinates ->
                    let
                        isCoordinatesInfoRecentEnoughToAttack =
                            case villageInfoCheckFromCoordinates nextCoordinates of
                                Nothing ->
                                    False

                                Just coordinatesInfo ->
                                    -- Avoid attacking a village that only recently was conquered by a player: Recheck the coordinates if the last check was too long ago.
                                    botState.timeInMilliseconds < coordinatesInfo.timeInMilliseconds + 10000
                    in
                    if isCoordinatesInfoRecentEnoughToAttack then
                        AttackAtCoordinates armyPreset nextCoordinates

                    else
                        GetVillageInfoAtCoordinates nextCoordinates
                )
            |> Maybe.map (ContinueWithThisVillage { remainingCapacityCommands = remainingCapacityCommands })
            |> Maybe.withDefault (CompletedThisVillage AllFarmsInSearchedAreaAlreadyAttackedInThisCycle)
            |> endDecisionPath


villageMatchesSettingsForFarm : BotSettings -> VillageCoordinates -> VillageByCoordinatesDetails -> Bool
villageMatchesSettingsForFarm settings villageCoordinates village =
    let
        ownedByCharacterToFarm =
            case village.characterName of
                Nothing ->
                    False

                Just characterName ->
                    if characterName == "" then
                        False

                    else
                        settings.playersToFarm |> List.member characterName
    in
    (((village.affiliation == Just AffiliationBarbarian)
        && (settings.farmBarbarianVillageMinimumPoints
                |> Maybe.map
                    (\farmBarbarianVillageMinimumPoints ->
                        case village.points of
                            Nothing ->
                                False

                            Just villagePoints ->
                                farmBarbarianVillageMinimumPoints <= villagePoints
                    )
                |> Maybe.withDefault True
           )
     )
        || ownedByCharacterToFarm
    )
        && (settings.farmAvoidCoordinates |> List.member villageCoordinates |> not)


pickBestMatchingArmyPresetForVillage :
    BotSettings
    -> List ArmyPreset
    -> ( Int, VillageDetails )
    -> (ArmyPreset -> DecisionPathNode VillageEndDecisionPathStructure)
    -> DecisionPathNode VillageEndDecisionPathStructure
pickBestMatchingArmyPresetForVillage settings presets ( villageId, villageDetails ) continueWithArmyPreset =
    if presets |> List.isEmpty then
        describeBranch "Did not find any army presets."
            (endDecisionPath (CompletedThisVillage NoMatchingArmyPresetEnabledForThisVillage))

    else
        let
            farmPresetFilter =
                settings.farmArmyPresetPatterns

            farmPresetsMaybeEmpty =
                presets
                    |> List.filter
                        (\preset ->
                            farmPresetFilter
                                |> List.any
                                    (\presetFilter ->
                                        stringContainsIgnoringCase presetFilter preset.name
                                    )
                        )
                    |> List.sortBy (.name >> String.toLower)
        in
        case farmPresetsMaybeEmpty of
            [] ->
                describeBranch
                    ("Found no army presets matching the patterns ["
                        ++ (farmPresetFilter |> List.map (String.Extra.surround "'") |> String.join ", ")
                        ++ "]."
                    )
                    (endDecisionPath (CompletedThisVillage NoMatchingArmyPresetEnabledForThisVillage))

            farmPresets ->
                case
                    farmPresets
                        |> List.filter (.assigned_villages >> List.member villageId)
                of
                    [] ->
                        describeBranch
                            ("Found " ++ (farmPresets |> List.length |> String.fromInt) ++ " army presets for farming, but none enabled for this village.")
                            (endDecisionPath (CompletedThisVillage NoMatchingArmyPresetEnabledForThisVillage))

                    farmPresetsEnabledForThisVillage ->
                        let
                            farmPresetsMatchingAvailableUnits =
                                farmPresetsEnabledForThisVillage
                                    |> List.filter
                                        (\preset ->
                                            preset.units
                                                |> Dict.toList
                                                |> List.all
                                                    (\( unitId, presetUnitCount ) ->
                                                        presetUnitCount
                                                            <= (villageDetails.units |> Dict.get unitId |> Maybe.map .available |> Maybe.withDefault 0)
                                                    )
                                        )
                        in
                        case farmPresetsMatchingAvailableUnits |> List.head of
                            Nothing ->
                                describeBranch
                                    ("Found " ++ (farmPresetsEnabledForThisVillage |> List.length |> String.fromInt) ++ " farming army presets enabled for this village, but not sufficient units available for any of these.")
                                    (endDecisionPath (CompletedThisVillage NotEnoughUnits))

                            Just bestMatchingPreset ->
                                describeBranch
                                    ("Best matching army preset for this village is '" ++ bestMatchingPreset.name ++ "'.")
                                    (continueWithArmyPreset bestMatchingPreset)


relativeCoordinatesToSearchForFarms : BotSettings -> List VillageCoordinates
relativeCoordinatesToSearchForFarms botSettings =
    coordinatesInCircleOrderedByDistance botSettings.farmBarbarianVillageMaximumDistance


relativeCoordinatesToSearchForFarmsPartitions : BotSettings -> List (List VillageCoordinates)
relativeCoordinatesToSearchForFarmsPartitions =
    relativeCoordinatesToSearchForFarms
        >> List.Extra.greedyGroupsOf 400


coordinatesInCircleOrderedByDistance : Int -> List VillageCoordinates
coordinatesInCircleOrderedByDistance radius =
    List.range -radius radius
        |> List.concatMap
            (\offsetX ->
                List.range -radius radius
                    |> List.map (\offsetY -> ( offsetX, offsetY ))
            )
        |> List.map (\( x, y ) -> ( { x = x, y = y }, x * x + y * y ))
        |> List.filter (\( _, distanceSquared ) -> distanceSquared <= radius * radius)
        |> List.sortBy Tuple.second
        |> List.map Tuple.first


offsetVillageCoordinates : VillageCoordinates -> VillageCoordinates -> VillageCoordinates
offsetVillageCoordinates coordsA coordsB =
    { x = coordsA.x + coordsB.x, y = coordsA.y + coordsB.y }


squareDistanceBetweenCoordinates : VillageCoordinates -> VillageCoordinates -> Int
squareDistanceBetweenCoordinates coordsA coordsB =
    let
        distX =
            coordsA.x - coordsB.x

        distY =
            coordsA.y - coordsB.y
    in
    distX * distX + distY * distY


componentsForRequestToPage : RequestToPageStructure -> { javascript : String, waitForCallbackDuration : Maybe Int }
componentsForRequestToPage requestToPage =
    case requestToPage of
        ReadRootInformationRequest ->
            { javascript = readRootInformationScript, waitForCallbackDuration = Nothing }

        ReadSelectedCharacterVillageDetailsRequest { villageId } ->
            { javascript = readSelectedCharacterVillageDetailsScript villageId, waitForCallbackDuration = Nothing }

        ReadArmyPresets ->
            { javascript = getPresetsScript, waitForCallbackDuration = Nothing }

        VillagesByCoordinatesRequest villagesArguments ->
            { javascript = startVillagesByCoordinatesScript villagesArguments
            , waitForCallbackDuration = Nothing
            }

        SendPresetAttackToCoordinatesRequest { coordinates, presetId } ->
            { javascript = startSendPresetAttackToCoordinatesScript coordinates { presetId = presetId }, waitForCallbackDuration = Nothing }

        VillageMenuActivateVillageRequest ->
            { javascript = villageMenuActivateVillageScript, waitForCallbackDuration = Nothing }

        ReadBattleReportListRequest ->
            { javascript = startRequestReportListScript { offset = 0, count = 25 }, waitForCallbackDuration = Just 3000 }


readRootInformationScript : String
readRootInformationScript =
    """
(function () {
tribalWars2 = (function(){
    if (typeof angular == 'undefined' || !(angular.element(document.body).injector().has('modelDataService'))) return { NotInTribalWars: true};

    modelDataService = angular.element(document.body).injector().get('modelDataService');
    selectedCharacter = modelDataService.getSelectedCharacter()
    if (selectedCharacter == null)
        return { NotInTribalWars: true};

    // Adapted formatting to strange syntax in google Chrome ->

    return { InTribalWars2 : {
            readyVillages : selectedCharacter.data.readyVillages
            , selectedVillageId : selectedCharacter.data.selectedVillage.data.villageId
            , getTotalVillagesResult : selectedCharacter.getTotalVillages()
            }
        };
})();

return JSON.stringify({ location : location.href, tribalWars2 : tribalWars2});
})()
"""


decodeResponseFromBrowser : Json.Decode.Decoder ResponseFromBrowser
decodeResponseFromBrowser =
    Json.Decode.oneOf
        [ decodeRootInformation |> Json.Decode.map RootInformation
        , decodeReadSelectedCharacterVillageDetailsResponse |> Json.Decode.map ReadSelectedCharacterVillageDetailsResponse
        , decodeVillagesByCoordinatesResponse |> Json.Decode.map VillagesByCoordinatesResponse
        , decodeRequestReportListResponse |> Json.Decode.map RequestReportListResponse
        , decodeGetPresetsResponse |> Json.Decode.map GetPresetsResponse
        , decodeActivatedVillageResponse |> Json.Decode.map (always ActivatedVillageResponse)
        , decodeSendPresetAttackToCoordinatesResponse |> Json.Decode.map SendPresetAttackToCoordinatesResponse
        ]


decodeRootInformation : Json.Decode.Decoder RootInformationStructure
decodeRootInformation =
    Json.Decode.map2 RootInformationStructure
        (Json.Decode.field "location" Json.Decode.string)
        (Json.Decode.field "tribalWars2"
            (Json.Decode.oneOf
                [ Json.Decode.field "NotInTribalWars" (Json.Decode.succeed Nothing)
                , Json.Decode.field "InTribalWars2" (decodeTribalWars2RootInformation |> Json.Decode.map Just)
                ]
            )
        )


decodeTribalWars2RootInformation : Json.Decode.Decoder TribalWars2RootInformation
decodeTribalWars2RootInformation =
    Json.Decode.map3 TribalWars2RootInformation
        (Json.Decode.field "readyVillages" (Json.Decode.list Json.Decode.int))
        (Json.Decode.field "selectedVillageId" Json.Decode.int)
        (Json.Decode.field "getTotalVillagesResult" Json.Decode.int)


readSelectedCharacterVillageDetailsScript : Int -> String
readSelectedCharacterVillageDetailsScript villageId =
    """
(function () {
    modelDataService = angular.element(document.body).injector().get('modelDataService');

    return JSON.stringify({ selectedCharacterVillage : modelDataService.getSelectedCharacter().data.villages[""" ++ "\"" ++ (villageId |> String.fromInt) ++ "\"" ++ """] });
})()
"""


decodeReadSelectedCharacterVillageDetailsResponse : Json.Decode.Decoder ReadSelectedCharacterVillageDetailsResponseStructure
decodeReadSelectedCharacterVillageDetailsResponse =
    Json.Decode.field "selectedCharacterVillage"
        (Json.Decode.map2 ReadSelectedCharacterVillageDetailsResponseStructure
            (Json.Decode.field "data" (Json.Decode.field "villageId" Json.Decode.int))
            decodeSelectedCharacterVillageDetails
        )


decodeSelectedCharacterVillageDetails : Json.Decode.Decoder VillageDetails
decodeSelectedCharacterVillageDetails =
    Json.Decode.map4 VillageDetails
        decodeVillageDetailsCoordinates
        (Json.Decode.field "data" (Json.Decode.field "name" Json.Decode.string))
        decodeVillageDetailsUnits
        decodeVillageDetailsCommands


decodeVillageDetailsCoordinates : Json.Decode.Decoder VillageCoordinates
decodeVillageDetailsCoordinates =
    Json.Decode.field "data"
        (Json.Decode.map2 VillageCoordinates
            (Json.Decode.field "x" Json.Decode.int)
            (Json.Decode.field "y" Json.Decode.int)
        )


decodeVillageDetailsUnits : Json.Decode.Decoder (Dict.Dict String VillageUnitCount)
decodeVillageDetailsUnits =
    Json.Decode.field "unitInfo"
        (Json.Decode.field "units"
            (Json.Decode.keyValuePairs decodeVillageDetailsUnitCount)
        )
        |> Json.Decode.map Dict.fromList


decodeVillageDetailsCommands : Json.Decode.Decoder VillageCommands
decodeVillageDetailsCommands =
    Json.Decode.at [ "data", "commands" ]
        (Json.Decode.map2 VillageCommands
            (Json.Decode.field "outgoing" (Json.Decode.list decodeVillageDetailsOutgoingCommand))
            (Json.Decode.field "incoming" (Json.Decode.list decodeVillageDetailsIncomingCommand))
        )


decodeVillageDetailsOutgoingCommand : Json.Decode.Decoder VillageCommand
decodeVillageDetailsOutgoingCommand =
    Json.Decode.map6 VillageCommand
        (Json.Decode.field "time_start" Json.Decode.int)
        (Json.Decode.field "time_completed" Json.Decode.int)
        (Json.Decode.Extra.optionalField "targetVillageId" Json.Decode.int)
        (Json.Decode.Extra.optionalField "targetX" Json.Decode.int)
        (Json.Decode.Extra.optionalField "targetY" Json.Decode.int)
        (Json.Decode.Extra.optionalField "returning" Json.Decode.bool)


decodeVillageDetailsIncomingCommand : Json.Decode.Decoder {}
decodeVillageDetailsIncomingCommand =
    Json.Decode.succeed {}


{-| 2020-01-16 Observed names: 'in\_town', 'support', 'total', 'available', 'own', 'inside', 'recruiting'
-}
decodeVillageDetailsUnitCount : Json.Decode.Decoder VillageUnitCount
decodeVillageDetailsUnitCount =
    Json.Decode.map VillageUnitCount
        (Json.Decode.field "available" Json.Decode.int)


startVillagesByCoordinatesScript : List { coordinates : VillageCoordinates, jumpToVillage : Bool } -> String
startVillagesByCoordinatesScript villages =
    let
        argumentJson =
            villages
                |> Json.Encode.list
                    (\village ->
                        [ ( "coordinates", village.coordinates |> jsonEncodeCoordinates )
                        , ( "jumpToVillage", village.jumpToVillage |> Json.Encode.bool )
                        ]
                            |> Json.Encode.object
                    )
                |> Json.Encode.encode 0
    in
    """
(async function readVillagesByCoordinates(argument) {

        autoCompleteService = angular.element(document.body).injector().get('autoCompleteService');
        mapService = angular.element(document.body).injector().get('mapService');

        function villageByCoordinatesPromise(coordinates) {
            return new Promise(resolve => {

                autoCompleteService.villageByCoordinates(coordinates, function(villageData) {
                    resolve(villageData);
                });
            });
            }

        const villagesData = [];

        for (const villageArgument of argument) {

            villageCoordinates = villageArgument.coordinates;
            jumpToVillage = villageArgument.jumpToVillage;

            villageData = await villageByCoordinatesPromise(villageCoordinates);

            villagesData.push({ villageCoordinates : villageCoordinates, villageData : villageData });

            if(jumpToVillage)
            {
                if(villageData.id == null)
                {
                    //  console.log("Did not find village at " + JSON.stringify(villageCoordinates));
                }
                else
                {
                    mapService.jumpToVillage(villageCoordinates.x, villageCoordinates.y, villageData.id);
                }
            }
        }

        // TODO: Add timeout for villagesData (wrapped in promise) to increment readFromGameConsecutiveTimeoutsCount?

        return JSON.stringify({ villagesByCoordinates : { argument : argument, villagesData : villagesData }});
})(""" ++ argumentJson ++ ")"


jsonEncodeCoordinates : { x : Int, y : Int } -> Json.Encode.Value
jsonEncodeCoordinates { x, y } =
    [ ( "x", x ), ( "y", y ) ] |> List.map (Tuple.mapSecond Json.Encode.int) |> Json.Encode.object


decodeVillagesByCoordinatesResponse : Json.Decode.Decoder VillagesByCoordinatesResponseStructure
decodeVillagesByCoordinatesResponse =
    Json.Decode.field "villagesByCoordinates"
        (Json.Decode.map2 VillagesByCoordinatesResponseStructure
            (Json.Decode.field "argument"
                (Json.Decode.list
                    (Json.Decode.map2 VillageByCoordinatesResponseStructure
                        (Json.Decode.field "coordinates"
                            (Json.Decode.map2 VillageCoordinates
                                (Json.Decode.field "x" Json.Decode.int)
                                (Json.Decode.field "y" Json.Decode.int)
                            )
                        )
                        (Json.Decode.field "jumpToVillage" Json.Decode.bool)
                    )
                )
            )
            (Json.Decode.field "villagesData" decodeVillagesByCoordinatesResult)
        )


decodeVillagesByCoordinatesResult : Json.Decode.Decoder (List { villageCoordinates : VillageCoordinates, villageData : VillageByCoordinatesResult })
decodeVillagesByCoordinatesResult =
    Json.Decode.list
        (Json.Decode.map2
            (\villageCoordinates villageData ->
                { villageCoordinates = villageCoordinates, villageData = villageData }
            )
            (Json.Decode.field "villageCoordinates"
                (Json.Decode.map2 VillageCoordinates
                    (Json.Decode.field "x" Json.Decode.int)
                    (Json.Decode.field "y" Json.Decode.int)
                )
            )
            (Json.Decode.field "villageData" decodeVillageByCoordinatesResult)
        )


decodeVillageByCoordinatesResult : Json.Decode.Decoder VillageByCoordinatesResult
decodeVillageByCoordinatesResult =
    Json.Decode.oneOf
        [ Json.Decode.keyValuePairs (Json.Decode.list Json.Decode.value)
            |> Json.Decode.andThen
                (\keyValuePairs ->
                    case keyValuePairs of
                        [ ( singlePropertyName, singlePropertyValue ) ] ->
                            if singlePropertyName == "villages" then
                                Json.Decode.succeed NoVillageThere

                            else
                                Json.Decode.fail "Other property name."

                        _ ->
                            Json.Decode.fail "Other number of properties."
                )
        , decodeVillageByCoordinatesDetails |> Json.Decode.map VillageThere
        ]


{-| 2020-03-22 There are also villages without 'points':
{ "x": 597, "y": 545, "name": "Freund einladen", "id": -2, "affiliation": "other" }

2020-12-21 Drklord discovered a case without 'affiliation' field at <https://forum.botlab.org/t/farm-manager-tribal-wars-2-farmbot/3038/207> :
{ "x" : 508, "y" : 456, "name" : "Invite a friend", "id" : -2 }

-}
decodeVillageByCoordinatesDetails : Json.Decode.Decoder VillageByCoordinatesDetails
decodeVillageByCoordinatesDetails =
    Json.Decode.map4 VillageByCoordinatesDetails
        (Json.Decode.field "id" Json.Decode.int)
        (jsonDecodeOptionalField "affiliation"
            (Json.Decode.string
                |> Json.Decode.map
                    (\affiliation ->
                        case affiliation |> String.toLower of
                            "barbarian" ->
                                AffiliationBarbarian

                            _ ->
                                AffiliationOther
                    )
            )
        )
        (Json.Decode.maybe (Json.Decode.field "points" Json.Decode.int))
        (Json.Decode.maybe (Json.Decode.field "character_name" Json.Decode.string))


getPresetsScript : String
getPresetsScript =
    """
(function getPresets() {
        presetListService = angular.element(document.body).injector().get('presetListService');

        return JSON.stringify({ getPresets: presetListService.getPresets() });
})()"""


decodeGetPresetsResponse : Json.Decode.Decoder (List ArmyPreset)
decodeGetPresetsResponse =
    Json.Decode.field "getPresets" (Json.Decode.keyValuePairs decodePreset)
        |> Json.Decode.map (List.map Tuple.second)


decodePreset : Json.Decode.Decoder ArmyPreset
decodePreset =
    Json.Decode.map4 ArmyPreset
        (Json.Decode.field "id" Json.Decode.int)
        (Json.Decode.field "name" Json.Decode.string)
        (Json.Decode.field "units" (Json.Decode.keyValuePairs Json.Decode.int)
            |> Json.Decode.map Dict.fromList
        )
        (Json.Decode.field "assigned_villages" (Json.Decode.list Json.Decode.int))


startSendPresetAttackToCoordinatesScript : { x : Int, y : Int } -> { presetId : Int } -> String
startSendPresetAttackToCoordinatesScript coordinates { presetId } =
    let
        argumentJson =
            [ ( "coordinates", coordinates |> jsonEncodeCoordinates )
            , ( "presetId", presetId |> Json.Encode.int )
            ]
                |> Json.Encode.object
                |> Json.Encode.encode 0
    in
    """
(function sendPresetAttackToCoordinates(argument) {
    let coordinates = argument.coordinates;
    let presetId = argument.presetId;

    let autoCompleteService = angular.element(document.body).injector().get('autoCompleteService');
    let socketService = angular.element(document.body).injector().get('socketService');
    let routeProvider = angular.element(document.body).injector().get('routeProvider');
    let mapService = angular.element(document.body).injector().get('mapService');
    let presetService = angular.element(document.body).injector().get('presetService');
    let groupService = injector.get('groupService');
    sendPresetAttack = function sendPresetAttack(presetId, targetVillageId) {
        //  TODO: Get 'type' from 'conf/commandTypes'.TYPES.ATTACK
        type = 'attack';

        socketService.emit(routeProvider.GET_ATTACKING_FACTOR, {
            'target_id' : targetVillageId
        }, function(data) {
            var targetData = {
                'id' : targetVillageId,
                'attackProtection' : data.attack_protection,
                'barbarianVillage' : data.owner_id === null
            };

            mapService.updateVillageOwner(targetData.id, data.owner_id);

            presetService.sendPreset(presetId, type, targetData.id, targetData.attackProtection, targetData.barbarianVillage, false, function() {
                //  $scope.closeWindow();
            });
        });
    };

	autoCompleteService.villageByCoordinates(coordinates, function(villageData) {
		//  console.log(JSON.stringify({ coordinates : coordinates, villageByCoordinates: villageData}));

		if(villageData.id == null)
		{
			//  console.log("Did not find village at " + JSON.stringify(coordinates));
			return; // No village here.
		}

		//  mapService.jumpToVillage(coordinates.x, coordinates.y, villageData.id);
		if(groupService.getVillageGroups(villageData.id).findIndex(z => z.icon == "-0020")!==-1)
		{
			//console.log('this village is already being attacked');
		}
		else if(villageData.report_result===0 || villageData.report_haul===1)
		{
			//if there is no last report, it will sendPresetAttack. If there was a full haul in the last attack, it will sendPresetAttack
			sendPresetAttack(presetId, villageData.id);
		}
		else
		{		
			//let attackInterval=argument.atkInterval*60
			let attackInterval = 61*60; //in seconds
			let raidBonus=JSON.parse(JSON.stringify(injector.get('modelDataService').getSelectedCharacter().data.effectList.effects.find(z => z.type == "farm_speed_increase").factor)) //tribe's 
			let selectedVillage = injector.get('modelDataService').getSelectedVillage();
			let rallyBonus=selectedVillage.buildingData.data.rally_point.specialFunction.currentValue/100;
			let originX; let targetX;
			if(selectedVillage.data.y%2 == 0 )
			{/*(if even)*/
				originX = selectedVillage.data.x - 0.5;
			} else
			{
				originX = selectedVillage.data.x;
			}			
			if(coordinates.y%2 == 0)
			{/*(if even)*/
				targetX = coordinates.x - 0.5;
			} else
			{
				targetX = coordinates.x;
			}			
			let distance = Math.sqrt((originX-targetX)*(originX-targetX)+0.75*(selectedVillage.data.y-coordinates.y)*(selectedVillage.data.y-coordinates.y));
			let presetUnits = injector.get('modelDataService').getPresetList().presets[presetId].units;
			let slowestWalk;
			if(presetUnits.light_cavalry>0 || presetUnits.mounted_archer>0)
			{
				slowestWalk=8;
			}
			if(presetUnits.heavy_cavalry>0)
			{
				slowestWalk=9;
			}
			if((presetUnits.axe+ presetUnits.archer+presetUnits.spear+presetUnits.doppelsoldner)>0)
			{
				slowestWalk=14;
			}	
			if(presetUnits.sword>0)
			{
				slowestWalk=18;
			}	
			if((presetUnits.ram+presetUnits.catapult)>0)
			{
				slowestWalk=24;
			}
			if(presetUnits.snob>0)
			{
				slowestWalk=35;
			}
			if(presetUnits.trebuchet>0)
			{
				slowestWalk=50;
			}
			if(typeof slowestWalk === 'undefined')
			{
				console.log('Error. Walk speed is zero');
			};
			let travelTime=Math.floor(distance*slowestWalk*60); //in seconds
			//otherwise we check how long it has been since we attacked, and how long it will take to reach the barb.
			if(villageData.report_result===1)
			{	
				let timePassed=Math.floor(Date.now()/1000)+travelTime-villageData.report_time_created;
				if(timePassed>attackInterval)
				{
					sendPresetAttack(presetId, villageData.id);
				}
				else
				{
					//console.log('Interval was short '+timePassed/60);
				}
			}
		}
	});
    return JSON.stringify({ startedSendPresetAttackByCoordinates : coordinates });
})(""" ++ argumentJson ++ ")"


decodeSendPresetAttackToCoordinatesResponse : Json.Decode.Decoder SendPresetAttackToCoordinatesResponseStructure
decodeSendPresetAttackToCoordinatesResponse =
    Json.Decode.field "startedSendPresetAttackByCoordinates"
        (Json.Decode.map2 VillageCoordinates
            (Json.Decode.field "x" Json.Decode.int)
            (Json.Decode.field "y" Json.Decode.int)
        )
        |> Json.Decode.map SendPresetAttackToCoordinatesResponseStructure


villageMenuActivateVillageScript : String
villageMenuActivateVillageScript =
    """
(function () {
    getXPathResultFirstNode = function getXPathResultFirstNode(xpath) {        
        return document.evaluate(xpath, document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue;
    };

    var contextMenuEntry = getXPathResultFirstNode("//*[contains(@class, 'context-menu-item') and contains(@class, 'activate')]//*[contains(@ng-click, 'openSubMenu')]");
    
    contextMenuEntry.click();

    return JSON.stringify({ activatedVillage : true });
})();
"""


decodeActivatedVillageResponse : Json.Decode.Decoder ()
decodeActivatedVillageResponse =
    Json.Decode.field "activatedVillage" (Json.Decode.succeed ())


{-| What values does `requestReportList` support for the `filters` parameter?
2020-05-20 I used `JSON.stringify` on a value for `filters` coming from the `ReportListController` (`$scope.activeFilters` in the calling site) and got this:

"{"BATTLE\_RESULTS":{"1":false,"2":false,"3":false},"BATTLE\_TYPES":{"attack":true,"defense":true,"support":true,"scouting":true},"OTHERS\_TYPES":{"trade":true,"system":true,"misc":true},"MISC":{"favourite":false,"full\_haul":false,"forwarded":false,"character":false}}"

The above `filters` variant was with all visible; at least that was the intention. Let's see what `filters` we find when using the filters in the UI:

Victory with casualties:

"{"BATTLE\_RESULTS":{"1":false,"2":true,"3":false},"BATTLE\_TYPES":{"attack":true,"defense":true,"support":true,"scouting":true},"OTHERS\_TYPES":{"trade":true,"system":true,"misc":true},"MISC":{"favourite":false,"full\_haul":false,"forwarded":false,"character":false}}"

Defeat:

"{"BATTLE\_RESULTS":{"1":false,"2":false,"3":true},"BATTLE\_TYPES":{"attack":true,"defense":true,"support":true,"scouting":true},"OTHERS\_TYPES":{"trade":true,"system":true,"misc":true},"MISC":{"favourite":false,"full\_haul":false,"forwarded":false,"character":false}}"

-}
startRequestReportListScript : { offset : Int, count : Int } -> String
startRequestReportListScript request =
    let
        argumentJson =
            [ ( "offset", request.offset |> Json.Encode.int )
            , ( "count", request.count |> Json.Encode.int )
            ]
                |> Json.Encode.object
                |> Json.Encode.encode 0
    in
    """
(async function requestReportList(argument) {

        reportService = angular.element(document.body).injector().get('reportService');

        function requestReportListAsync(argument) {
            return new Promise(resolve => {

                reportService.requestReportList('battle', argument.offset, argument.count, null, { "BATTLE_RESULTS": { "1": false, "2": false, "3": false }, "BATTLE_TYPES": { "attack": true, "defense": true, "support": true, "scouting": true }, "OTHERS_TYPES": { "trade": true, "system": true, "misc": true }, "MISC": { "favourite": false, "full_haul": false, "forwarded": false, "character": false } }, resolve);
            });
            }

        reportListData = await requestReportListAsync(argument);

        return JSON.stringify({ startedRequestReportList : { argument : argument, reportListData : reportListData } });
})(""" ++ argumentJson ++ ")"


decodeRequestReportListResponse : Json.Decode.Decoder RequestReportListResponseStructure
decodeRequestReportListResponse =
    Json.Decode.field "startedRequestReportList"
        (Json.Decode.map2 RequestReportListResponseStructure
            (Json.Decode.field "argument"
                (Json.Decode.map2 (\offset count -> { offset = offset, count = count })
                    (Json.Decode.field "offset" Json.Decode.int)
                    (Json.Decode.field "count" Json.Decode.int)
                )
            )
            (Json.Decode.field "reportListData" decodeRequestReportListData)
        )


decodeRequestReportListData : Json.Decode.Decoder RequestReportListCallbackDataStructure
decodeRequestReportListData =
    Json.Decode.map3 RequestReportListCallbackDataStructure
        (Json.Decode.field "offset" Json.Decode.int)
        (Json.Decode.field "total" Json.Decode.int)
        (Json.Decode.field "reports" (Json.Decode.list decodeRequestReportListCallbackDataReport))


decodeRequestReportListCallbackDataReport : Json.Decode.Decoder RequestReportListCallbackDataReportStructure
decodeRequestReportListCallbackDataReport =
    Json.Decode.map3 RequestReportListCallbackDataReportStructure
        (Json.Decode.field "id" Json.Decode.int)
        (Json.Decode.field "time_created" Json.Decode.int)
        (Json.Decode.field "result" decodeBattleReportResult)


decodeBattleReportResult : Json.Decode.Decoder BattleReportResult
decodeBattleReportResult =
    Json.Decode.int
        |> Json.Decode.andThen
            (\resultInteger ->
                [ ( 1, BattleReportResult_NO_CASUALTIES )
                , ( 2, BattleReportResult_CASUALTIES )
                , ( 3, BattleReportResult_DEFEAT )
                ]
                    |> Dict.fromList
                    |> Dict.get resultInteger
                    |> Maybe.map Json.Decode.succeed
                    |> Maybe.withDefault (Json.Decode.fail ("Unknown report result type '" ++ (resultInteger |> String.fromInt) ++ "'"))
            )


statusMessageFromState : BotState -> { activityDecisionStages : List String } -> String
statusMessageFromState state { activityDecisionStages } =
    let
        sentAttacks =
            countSentAttacks state

        describeSessionPerformance =
            [ ( "attacks sent", sentAttacks.inSession )
            , ( "coordinates read", state.numberOfReadsFromCoordinates )
            , ( "completed farm cycles", state.completedFarmCycles |> List.length )
            ]
                |> List.map (\( metric, amount ) -> metric ++ ": " ++ (amount |> String.fromInt))
                |> String.join ", "

        jsRunResult =
            "lastRunJavascriptResult:\n"
                ++ (state.lastRunJavascriptResult |> Maybe.map .response |> describeMaybe describeRunJavascriptInCurrentPageResponseStructure)

        villagesByCoordinates =
            state.coordinatesLastCheck
                |> Dict.toList
                |> List.filterMap
                    (\( coordinates, scanResult ) ->
                        case scanResult.result of
                            NoVillageThere ->
                                Nothing

                            VillageThere village ->
                                Just ( coordinates, village )
                    )
                |> Dict.fromList

        barbarianVillages =
            villagesByCoordinates |> Dict.filter (\_ village -> village.affiliation == Just AffiliationBarbarian)

        villagesMatchingSettingsForFarm =
            villagesByCoordinates
                |> Dict.filter (\( x, y ) village -> villageMatchesSettingsForFarm state.settings { x = x, y = y } village)

        numberOfVillagesAvoidedBySettings =
            (barbarianVillages |> Dict.size) - (villagesMatchingSettingsForFarm |> Dict.size)

        coordinatesChecksReport =
            "Checked "
                ++ (state.coordinatesLastCheck |> Dict.size |> String.fromInt)
                ++ " unique coordinates and found "
                ++ (villagesByCoordinates |> Dict.size |> String.fromInt)
                ++ " villages, "
                ++ (barbarianVillages |> Dict.size |> String.fromInt)
                ++ " of which are barbarian villages"
                ++ (if numberOfVillagesAvoidedBySettings < 1 then
                        ""

                    else
                        " (" ++ (numberOfVillagesAvoidedBySettings |> String.fromInt) ++ " avoided by current settings)"
                   )
                ++ "."

        sentAttacksReportPartCurrentCycle =
            case sentAttacks.inCurrentCycle of
                Nothing ->
                    []

                Just inCurrentCycle ->
                    [ "Sent " ++ (inCurrentCycle |> String.fromInt) ++ " attacks in the current cycle." ]

        completedFarmCyclesReportLines =
            case state.completedFarmCycles |> List.head of
                Nothing ->
                    []

                Just lastCompletedFarmCycle ->
                    let
                        completionAgeInMinutes =
                            (state.timeInMilliseconds // 1000 - lastCompletedFarmCycle.completionTime) // 60

                        farmCycleConclusionDescription =
                            describeFarmCycleConclusion lastCompletedFarmCycle
                    in
                    [ "Completed "
                        ++ (state.completedFarmCycles |> List.length |> describeOrdinalNumber)
                        ++ " farm cycle "
                        ++ (completionAgeInMinutes |> String.fromInt)
                        ++ " minutes ago with "
                        ++ farmCycleConclusionDescription.villagesReport
                        ++ " "
                        ++ farmCycleConclusionDescription.attacksReport
                    , "---"
                    ]

        inGameReport =
            case state.gameRootInformationResult of
                Nothing ->
                    "I did not yet read game root information. Please log in to the game so that you see your villages."

                Just gameRootInformationResult ->
                    let
                        gameRootInformation =
                            gameRootInformationResult.gameRootInformation

                        ownVillagesReport =
                            "Found "
                                ++ (gameRootInformation.getTotalVillagesResult |> String.fromInt)
                                ++ " own villages"
                                ++ (if areAllVillagesLoaded gameRootInformation then
                                        ""

                                    else
                                        ", but only " ++ (gameRootInformation.readyVillages |> List.length |> String.fromInt) ++ " loaded yet"
                                   )
                                ++ "."
                    in
                    ownVillagesReport

        parseResponseErrorReport =
            case state.parseResponseError of
                Nothing ->
                    ""

                Just parseResponseError ->
                    Json.Decode.errorToString parseResponseError

        debugInspectionLines =
            [ jsRunResult ]

        enableDebugInspection =
            False

        reloadReportLines =
            state
                |> lastStartWebBrowserAgeInSecondsFromState
                |> Maybe.map
                    (\lastReloadPageAgeInSeconds ->
                        [ "Started the web browser "
                            ++ (state.startWebBrowserCount |> String.fromInt)
                            ++ " times, last time was "
                            ++ ((lastReloadPageAgeInSeconds // 60) |> String.fromInt)
                            ++ " minutes ago."
                        ]
                    )
                |> Maybe.withDefault []

        readBattleReportsReport =
            case state.lastRequestReportListResult of
                Nothing ->
                    "Did not yet read battle reports."

                Just requestReportListResult ->
                    let
                        responseReport =
                            "Received IDs of " ++ (requestReportListResult.reportListData.reports |> List.length |> String.fromInt) ++ " reports"
                    in
                    "Read the list of battle reports: " ++ responseReport

        settingsReport =
            "Settings: "
                ++ ([ ( "cycles", state.settings.numberOfFarmCycles |> String.fromInt )
                    , ( "breaks"
                      , (state.settings.breakDurationMinutes.minimum |> String.fromInt)
                            ++ " - "
                            ++ (state.settings.breakDurationMinutes.maximum |> String.fromInt)
                      )
                    , ( "max dist", state.settings.farmBarbarianVillageMaximumDistance |> String.fromInt )
                    , ( "web-browser-user-profile-id", state.settings.webBrowserUserProfileId )
                    ]
                        |> List.map (\( settingName, settingValue ) -> settingName ++ ": " ++ settingValue)
                        |> String.join ", "
                   )

        activityDescription =
            activityDecisionStages
                |> List.indexedMap
                    (\decisionLevel -> (++) (("+" |> List.repeat (decisionLevel + 1) |> String.join "") ++ " "))
                |> String.join "\n"
    in
    [ [ "Session performance: " ++ describeSessionPerformance ]
    , completedFarmCyclesReportLines
    , sentAttacksReportPartCurrentCycle
    , [ coordinatesChecksReport ]
    , [ inGameReport ]
    , [ readBattleReportsReport ]
    , reloadReportLines
    , [ parseResponseErrorReport ]
    , if enableDebugInspection then
        debugInspectionLines

      else
        []
    , [ "", "Current activity:" ]
    , [ activityDescription ]
    , [ "---", settingsReport ]
    ]
        |> List.concat
        |> String.join "\n"


areAllVillagesLoaded : TribalWars2RootInformation -> Bool
areAllVillagesLoaded rootInfo =
    rootInfo.getTotalVillagesResult == (rootInfo.readyVillages |> List.length)


describeOrdinalNumber : Int -> String
describeOrdinalNumber number =
    [ ( 1, "first" )
    , ( 2, "second" )
    , ( 3, "third" )
    , ( 4, "fourth" )
    ]
        |> Dict.fromList
        |> Dict.get number
        |> Maybe.withDefault ((number |> String.fromInt) ++ "th")


describeFarmCycleConclusion : FarmCycleConclusion -> { villagesReport : String, attacksReport : String }
describeFarmCycleConclusion conclusion =
    let
        countVillagesForResultKind villageResultKind =
            conclusion.villagesResults
                |> Dict.values
                |> List.filter ((==) villageResultKind)
                |> List.length

        villagesResultsReport =
            [ NoMatchingArmyPresetEnabledForThisVillage
            , ExhaustedAttackLimit
            , NotEnoughUnits
            , AllFarmsInSearchedAreaAlreadyAttackedInThisCycle
            ]
                |> List.filterMap
                    (\villageResultKind ->
                        let
                            villagesWithThisResult =
                                countVillagesForResultKind villageResultKind
                        in
                        if villagesWithThisResult < 1 then
                            Nothing

                        else
                            Just
                                ((describeVillageCompletion villageResultKind).cycleStatsGroup
                                    ++ ": "
                                    ++ (villagesWithThisResult |> String.fromInt)
                                )
                    )
                |> String.join ", "

        durationInMinutes =
            (conclusion.completionTime - conclusion.beginTime) // 60
    in
    { villagesReport =
        (conclusion.villagesResults |> Dict.size |> String.fromInt)
            ++ " villages ("
            ++ villagesResultsReport
            ++ ")."
    , attacksReport =
        "Sent "
            ++ (conclusion.attacksCount |> String.fromInt)
            ++ " attacks in "
            ++ (durationInMinutes |> String.fromInt)
            ++ " minutes."
    }


countSentAttacks : BotState -> { inSession : Int, inCurrentCycle : Maybe Int }
countSentAttacks state =
    let
        countInFarmCycle =
            .sentAttackByCoordinates >> Dict.size

        attackSentInEarlierCycles =
            state.completedFarmCycles |> List.map .attacksCount |> List.sum

        inCurrentCycle =
            case state.farmState of
                InFarmCycle _ farmCycle ->
                    Just (farmCycle |> countInFarmCycle)

                InBreak _ ->
                    Nothing
    in
    { inSession = attackSentInEarlierCycles + (inCurrentCycle |> Maybe.withDefault 0), inCurrentCycle = inCurrentCycle }


villageCoordinatesDisplayText : VillageCoordinates -> String
villageCoordinatesDisplayText { x, y } =
    (x |> String.fromInt) ++ "|" ++ (y |> String.fromInt)


describeRunJavascriptInCurrentPageResponseStructure : BotFramework.RunJavascriptInCurrentPageResponseStructure -> String
describeRunJavascriptInCurrentPageResponseStructure response =
    "{ webBrowserAvailable = "
        ++ (if response.webBrowserAvailable then
                "true"

            else
                "false"
           )
        ++ ", directReturnValueAsString = "
        ++ describeString 300 response.directReturnValueAsString
        ++ "\n"
        ++ ", callbackReturnValueAsString = "
        ++ describeMaybe (describeString 300) response.callbackReturnValueAsString
        ++ "\n}"


describeString : Int -> String -> String
describeString maxLength string =
    "\"" ++ (string |> stringEllipsis maxLength "...") ++ "\""


describeMaybe : (just -> String) -> Maybe just -> String
describeMaybe describeJust maybe =
    case maybe of
        Nothing ->
            "Nothing"

        Just just ->
            describeJust just


stringEllipsis : Int -> String -> String -> String
stringEllipsis howLong append string =
    if String.length string <= howLong then
        string

    else
        String.left (howLong - String.length append) string ++ append


nothingFromIntIfGreaterThan : Int -> Int -> Maybe Int
nothingFromIntIfGreaterThan limit originalInt =
    if limit < originalInt then
        Nothing

    else
        Just originalInt


jsonDecodeOptionalField : String -> Json.Decode.Decoder a -> Json.Decode.Decoder (Maybe a)
jsonDecodeOptionalField fieldName decoder =
    let
        finishDecoding json =
            case Json.Decode.decodeValue (Json.Decode.field fieldName Json.Decode.value) json of
                Ok _ ->
                    -- The field is present, so run the decoder on it.
                    Json.Decode.map Just (Json.Decode.field fieldName decoder)

                Err _ ->
                    -- The field was missing, which is fine!
                    Json.Decode.succeed Nothing
    in
    Json.Decode.value
        |> Json.Decode.andThen finishDecoding
