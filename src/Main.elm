port module Main exposing (main)

import Array
import Browser
import Data exposing (Choice(..), Dish, Meal, Season, State, Week)
import Day
import Dict exposing (Dict)
import Draw
import File exposing (File)
import File.Download
import File.Select
import Html exposing (Html, a, article, button, div, form, h1, h2, header, input, label, li, main_, nav, option, p, section, select, small, span, strong, text, ul)
import Html.Attributes as A
import Html.Events as Ev
import Json.Decode as D
import Json.Encode as E
import Random
import Set exposing (Set)
import Task
import Time
import Url


port save : E.Value -> Cmd msg


{-| État fusionné reçu du foyer (voir src/sync.js).
-}
port remoteState : (D.Value -> msg) -> Sub msg


port syncStatus : (String -> msg) -> Sub msg


main : Program D.Value Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }



-- MODÈLE


type Page
    = Semaine
    | Plats
    | Idees


type Field
    = Starch
    | Protein
    | Style


type alias Rolling =
    { tick : Int
    , order : List Int
    }


type alias DishForm =
    { name : String
    , url : String
    , boite : Bool
    , seasons : List Season
    , starch : String
    , protein : String
    , style : String
    }


type alias Model =
    { state : State
    , today : Int
    , monday : Int
    , page : Page
    , open : Maybe Int
    , search : String
    , rolling : Maybe Rolling
    , form : DishForm
    , editing : Maybe Dish
    , confirmDelete : Maybe String
    , dishSearch : String
    , seasonFilter : Maybe Season
    , notice : Maybe String
    , sync : String
    }


emptyForm : DishForm
emptyForm =
    { name = "", url = "", boite = True, seasons = Data.allSeasons, starch = "", protein = "", style = "" }


init : D.Value -> ( Model, Cmd Msg )
init flags =
    let
        today =
            D.decodeValue (D.field "today" D.int) flags |> Result.withDefault 0

        state =
            D.decodeValue (D.field "saved" Data.decoder) flags |> Result.withDefault Data.initial

        current =
            Day.mondayOf today
    in
    ( { state = state
      , today = today

      -- le week-end, on prépare la semaine suivante
      , monday =
            if Day.weekday today >= 5 then
                current + 7

            else
                current
      , page = Semaine
      , open = Nothing
      , search = ""
      , rolling = Nothing
      , form = emptyForm
      , editing = Nothing
      , confirmDelete = Nothing
      , dishSearch = ""
      , seasonFilter = Nothing
      , notice = Nothing
      , sync = D.decodeValue (D.field "sync" D.string) flags |> Result.withDefault ""
      }
      -- réécrit les données migrées (nouveaux plats de départ, saisons)
    , save (Data.encode state)
    )



-- MISE À JOUR


type Msg
    = SetPage Page
    | PrevWeek
    | NextWeek
    | ThisWeek
    | Roll
    | Rolled (List ( Int, String ))
    | Tick
    | Toggle Int
    | Search String
    | SetChoice Int Choice
    | ToggleLock Int
    | RerollOne Int
    | RerolledOne Int (Maybe String)
    | ClearWeek
    | FormName String
    | FormUrl String
    | FormBoite Bool
    | FormCategory Field String
    | FormSeason Season
    | AddDish
    | StartEdit Dish
    | EditName String
    | EditUrl String
    | EditBoite Bool
    | EditCategory Field String
    | EditSeason Season
    | SaveEdit
    | CancelEdit
    | AskDelete String
    | ConfirmDelete String
    | DishSearch String
    | SeasonFilter (Maybe Season)
    | Export
    | ImportRequested
    | ImportSelected File
    | ImportLoaded String
    | DismissNotice
    | AdoptIdea String
    | DismissIdea String
    | RestoreIdeas
    | RemoteState D.Value
    | SyncStatus String


stopTick : Int -> Int
stopTick k =
    8 + 2 * k


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        SetPage page ->
            ( { model | page = page, open = Nothing, notice = Nothing }, Cmd.none )

        PrevWeek ->
            ( { model | monday = model.monday - 7, open = Nothing, rolling = Nothing }, Cmd.none )

        NextWeek ->
            ( { model | monday = model.monday + 7, open = Nothing, rolling = Nothing }, Cmd.none )

        ThisWeek ->
            ( { model | monday = Day.mondayOf model.today, open = Nothing, rolling = Nothing }, Cmd.none )

        Roll ->
            let
                week =
                    currentWeek model

                slots =
                    List.range 0 13
                        |> List.filter (\slot -> rerollable (Data.mealAt slot week))
                        |> List.map (\slot -> ( slot, Data.feedsLeftovers slot ))

                kept =
                    List.range 0 13
                        |> List.filterMap
                            (\slot ->
                                let
                                    meal =
                                        Data.mealAt slot week
                                in
                                if meal.locked then
                                    Data.dishIdOf meal.choice

                                else
                                    Nothing
                            )
                        |> Set.fromList
            in
            ( { model | open = Nothing, notice = Nothing }
            , Random.generate Rolled (Draw.pickMany (weekSeason model) model.state.dishes (recency model) kept slots)
            )

        Rolled picks ->
            let
                ( next, cmd ) =
                    updateWeek
                        (\week -> List.foldl (\( slot, dishId ) acc -> setMeal slot (\meal -> { meal | choice = Picked dishId }) acc) week picks)
                        model
            in
            ( { next
                | rolling =
                    if List.isEmpty picks then
                        Nothing

                    else
                        Just { tick = 0, order = List.sort (List.map Tuple.first picks) }
              }
            , cmd
            )

        Tick ->
            case model.rolling of
                Nothing ->
                    ( model, Cmd.none )

                Just rolling ->
                    if rolling.tick > stopTick (List.length rolling.order - 1) + 12 then
                        ( { model | rolling = Nothing }, Cmd.none )

                    else
                        ( { model | rolling = Just { rolling | tick = rolling.tick + 1 } }, Cmd.none )

        Toggle slot ->
            ( { model
                | open =
                    if model.open == Just slot then
                        Nothing

                    else
                        Just slot
                , search = ""
              }
            , Cmd.none
            )

        Search query ->
            ( { model | search = query }, Cmd.none )

        SetChoice slot choice ->
            updateWeek (setMeal slot (\meal -> { meal | choice = choice })) { model | open = Nothing, search = "" }

        ToggleLock slot ->
            updateWeek (setMeal slot (\meal -> { meal | locked = not meal.locked })) model

        RerollOne slot ->
            let
                week =
                    currentWeek model

                used =
                    List.range 0 13
                        |> List.filterMap (\other -> Data.dishIdOf (Data.mealAt other week).choice)
                        |> Set.fromList
            in
            ( model
            , Random.generate (RerolledOne slot)
                (Draw.pick (weekSeason model) model.state.dishes (recency model) used (Data.feedsLeftovers slot))
            )

        RerolledOne slot picked ->
            case picked of
                Just dishId ->
                    let
                        ( next, cmd ) =
                            updateWeek (setMeal slot (\meal -> { meal | choice = Picked dishId })) model
                    in
                    ( { next | rolling = Just { tick = 0, order = [ slot ] } }, cmd )

                Nothing ->
                    ( model, Cmd.none )

        ClearWeek ->
            updateWeek (\_ -> Data.emptyWeek) { model | open = Nothing, rolling = Nothing }

        FormName value ->
            ( { model | form = setName value model.form }, Cmd.none )

        FormUrl value ->
            ( { model | form = setUrl value model.form }, Cmd.none )

        FormBoite value ->
            ( { model | form = setBoite value model.form }, Cmd.none )

        FormCategory field value ->
            ( { model | form = setCategory field value model.form }, Cmd.none )

        FormSeason season ->
            ( { model | form = toggleSeasonOf season model.form }, Cmd.none )

        AddDish ->
            let
                name =
                    String.trim model.form.name
            in
            if String.isEmpty name then
                ( model, Cmd.none )

            else
                let
                    dish =
                        { id = Data.uniqueId name model.state.dishes
                        , name = name
                        , url = String.trim model.form.url
                        , boite = model.form.boite
                        , seasons = orAllSeasons model.form.seasons
                        , starch = model.form.starch
                        , protein = model.form.protein
                        , style = model.form.style
                        }
                in
                updateState (\state -> { state | dishes = state.dishes ++ [ dish ] })
                    { model | form = emptyForm, notice = Just ("« " ++ name ++ " » ajouté") }

        StartEdit dish ->
            ( { model | editing = Just dish, confirmDelete = Nothing }, Cmd.none )

        EditName value ->
            ( { model | editing = Maybe.map (setName value) model.editing }, Cmd.none )

        EditUrl value ->
            ( { model | editing = Maybe.map (setUrl value) model.editing }, Cmd.none )

        EditBoite value ->
            ( { model | editing = Maybe.map (setBoite value) model.editing }, Cmd.none )

        EditCategory field value ->
            ( { model | editing = Maybe.map (setCategory field value) model.editing }, Cmd.none )

        EditSeason season ->
            ( { model | editing = Maybe.map (toggleSeasonOf season) model.editing }, Cmd.none )

        SaveEdit ->
            case model.editing of
                Just edited ->
                    if String.isEmpty (String.trim edited.name) then
                        ( model, Cmd.none )

                    else
                        updateState
                            (\state ->
                                { state
                                    | dishes =
                                        List.map
                                            (\dish ->
                                                if dish.id == edited.id then
                                                    { edited | name = String.trim edited.name, url = String.trim edited.url, seasons = orAllSeasons edited.seasons }

                                                else
                                                    dish
                                            )
                                            state.dishes
                                }
                            )
                            { model | editing = Nothing }

                Nothing ->
                    ( model, Cmd.none )

        CancelEdit ->
            ( { model | editing = Nothing }, Cmd.none )

        AskDelete dishId ->
            ( { model | confirmDelete = Just dishId, editing = Nothing }, Cmd.none )

        ConfirmDelete dishId ->
            updateState (\state -> { state | dishes = List.filter (\dish -> dish.id /= dishId) state.dishes })
                { model | confirmDelete = Nothing }

        DishSearch query ->
            ( { model | dishSearch = query }, Cmd.none )

        SeasonFilter filter ->
            ( { model | seasonFilter = filter }, Cmd.none )

        Export ->
            ( model, File.Download.string "popote.json" "application/json" (E.encode 2 (Data.encode model.state)) )

        ImportRequested ->
            ( model, File.Select.file [ "application/json", ".json" ] ImportSelected )

        ImportSelected file ->
            ( model, Task.perform ImportLoaded (File.toString file) )

        ImportLoaded raw ->
            case D.decodeString Data.decoder raw of
                Ok state ->
                    ( { model | state = state, notice = Just "Import réussi" }, save (Data.encode state) )

                Err _ ->
                    ( { model | notice = Just "Fichier illisible : rien n'a été importé" }, Cmd.none )

        DismissNotice ->
            ( { model | notice = Nothing }, Cmd.none )

        RemoteState value ->
            case D.decodeValue Data.decoder value of
                Ok state ->
                    -- réécrit pour garder le stockage local aligné sur les migrations
                    ( { model | state = state }, save (Data.encode state) )

                Err _ ->
                    ( model, Cmd.none )

        SyncStatus text ->
            ( { model | sync = text }, Cmd.none )

        AdoptIdea name ->
            case List.filter (\sd -> sd.name == name) Data.ideas of
                sd :: _ ->
                    updateState (\state -> { state | dishes = state.dishes ++ [ Data.toDish state.dishes sd ] })
                        { model | notice = Just ("« " ++ name ++ " » ajouté à vos plats") }

                [] ->
                    ( model, Cmd.none )

        DismissIdea name ->
            updateState (\state -> { state | dismissed = Data.normalize name :: state.dismissed }) model

        RestoreIdeas ->
            updateState (\state -> { state | dismissed = [] }) model


setName : String -> { r | name : String } -> { r | name : String }
setName value r =
    { r | name = value }


setUrl : String -> { r | url : String } -> { r | url : String }
setUrl value r =
    { r | url = value }


setCategory : Field -> String -> { r | starch : String, protein : String, style : String } -> { r | starch : String, protein : String, style : String }
setCategory field value r =
    case field of
        Starch ->
            { r | starch = value }

        Protein ->
            { r | protein = value }

        Style ->
            { r | style = value }


setBoite : Bool -> { r | boite : Bool } -> { r | boite : Bool }
setBoite value r =
    { r | boite = value }


toggleSeasonOf : Season -> { r | seasons : List Season } -> { r | seasons : List Season }
toggleSeasonOf season r =
    { r | seasons = Data.toggleSeason season r.seasons }


{-| Aucune saison cochée : le plat se mange toute l'année.
-}
orAllSeasons : List Season -> List Season
orAllSeasons seasons =
    if List.isEmpty seasons then
        Data.allSeasons

    else
        seasons


{-| Saison de la semaine affichée (celle de son jeudi).
-}
weekSeason : Model -> Season
weekSeason model =
    Data.seasonOf (model.monday + 3)


{-| Repas que le prochain tirage remplacera.
-}
rerollable : Meal -> Bool
rerollable meal =
    not meal.locked
        && (case meal.choice of
                Picked _ ->
                    True

                Unset ->
                    True

                _ ->
                    False
           )


currentWeek : Model -> Week
currentWeek model =
    Data.weekOf model.monday model.state


recency : Model -> Dict String Int
recency model =
    Draw.recency model.monday model.state.weeks


updateState : (State -> State) -> Model -> ( Model, Cmd Msg )
updateState f model =
    let
        state =
            f model.state
    in
    ( { model | state = state }, save (Data.encode state) )


updateWeek : (Week -> Week) -> Model -> ( Model, Cmd Msg )
updateWeek f model =
    updateState
        (\state -> { state | weeks = Dict.insert model.monday (f (Data.weekOf model.monday state)) state.weeks })
        model


setMeal : Int -> (Meal -> Meal) -> Week -> Week
setMeal slot f week =
    Dict.insert slot (f (Data.mealAt slot week)) week


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ remoteState RemoteState
        , syncStatus SyncStatus
        , case model.rolling of
            Just _ ->
                Time.every 65 (\_ -> Tick)

            Nothing ->
                Sub.none
        ]



-- VUE


view : Model -> Html Msg
view model =
    div [ A.class "app" ]
        [ header [ A.class "top" ]
            [ h1 [ A.class "brand" ] [ span [ A.class "brand-mark" ] [ text "🍲" ], text "La Popote" ]
            , nav [ A.class "tabs" ]
                [ tab model Semaine "Semaine"
                , tab model Plats ("Plats · " ++ String.fromInt (List.length model.state.dishes))
                , tab model Idees ("💡 Idées · " ++ String.fromInt (List.length (Data.openIdeas model.state)))
                ]
            ]
        , case model.notice of
            Just notice ->
                button [ A.class "notice", Ev.onClick DismissNotice ] [ text notice ]

            Nothing ->
                text ""
        , main_ []
            [ case model.page of
                Semaine ->
                    viewWeek model

                Plats ->
                    viewDishes model

                Idees ->
                    viewIdeas model
            ]
        ]


tab : Model -> Page -> String -> Html Msg
tab model page caption =
    button [ A.class "tab", A.classList [ ( "active", model.page == page ) ], Ev.onClick (SetPage page) ] [ text caption ]



-- SEMAINE


type Reel
    = Still
    | Spinning String
    | Landed


reelFor : Model -> Int -> Reel
reelFor model slot =
    case model.rolling of
        Nothing ->
            Still

        Just rolling ->
            case indexOf slot rolling.order of
                Nothing ->
                    Still

                Just k ->
                    if rolling.tick < stopTick k then
                        Spinning (reelName model.state.dishes (rolling.tick * 7 + k * 13))

                    else
                        Landed


indexOf : a -> List a -> Maybe Int
indexOf x xs =
    xs
        |> List.indexedMap Tuple.pair
        |> List.filter (\( _, y ) -> y == x)
        |> List.head
        |> Maybe.map Tuple.first


reelName : List Dish -> Int -> String
reelName dishes n =
    let
        names =
            Array.fromList (List.map .name dishes)
    in
    Array.get (modBy (max 1 (Array.length names)) n) names |> Maybe.withDefault "…"


dishById : Model -> String -> Maybe Dish
dishById model dishId =
    List.filter (\dish -> dish.id == dishId) model.state.dishes |> List.head


dishName : Model -> String -> String
dishName model dishId =
    dishById model dishId |> Maybe.map .name |> Maybe.withDefault "Plat supprimé"


relativeWeek : Model -> String
relativeWeek model =
    let
        diff =
            (model.monday - Day.mondayOf model.today) // 7
    in
    if diff == 0 then
        "Cette semaine"

    else if diff == 1 then
        "Semaine prochaine"

    else if diff == -1 then
        "Semaine dernière"

    else if diff > 0 then
        "Dans " ++ String.fromInt diff ++ " semaines"

    else
        "Il y a " ++ String.fromInt (abs diff) ++ " semaines"


viewWeek : Model -> Html Msg
viewWeek model =
    let
        week =
            currentWeek model

        rolling =
            model.rolling /= Nothing

        picked =
            List.range 0 13 |> List.filterMap (\slot -> Data.dishIdOf (Data.mealAt slot week).choice)

        toRoll =
            List.length (List.filter (\slot -> rerollable (Data.mealAt slot week)) (List.range 0 13))

        isCurrent =
            model.monday == Day.mondayOf model.today
    in
    section [ A.class "week" ]
        [ div [ A.class "week-nav" ]
            [ button [ A.class "round", Ev.onClick PrevWeek, A.title "Semaine précédente" ] [ text "‹" ]
            , div [ A.class "week-title" ]
                [ small [] [ text (relativeWeek model ++ " · " ++ Data.seasonIcon (weekSeason model) ++ " " ++ Data.seasonName (weekSeason model)) ]
                , strong [] [ text (Day.weekLabel model.monday) ]
                , if isCurrent then
                    text ""

                  else
                    button [ A.class "link", Ev.onClick ThisWeek ] [ text "revenir à aujourd'hui" ]
                ]
            , button [ A.class "round", Ev.onClick NextWeek, A.title "Semaine suivante" ] [ text "›" ]
            ]
        , button
            [ A.class "roll"
            , A.classList [ ( "is-rolling", rolling ) ]
            , Ev.onClick Roll
            , A.disabled (rolling || toRoll == 0 || List.isEmpty model.state.dishes)
            ]
            [ span [ A.class "dice" ] [ text "🎲" ]
            , text
                (if rolling then
                    "Ça mijote…"

                 else if List.isEmpty picked then
                    "Tirer la semaine"

                 else if toRoll == 0 then
                    "Semaine bouclée ✓"

                 else
                    "Relancer " ++ String.fromInt toRoll ++ " repas"
                )
            ]
        , p [ A.class "hint" ]
            [ text
                (if List.isEmpty picked then
                    "Un clic pour tirer les repas de la semaine."

                 else
                    "Garde 🔒 les plats qui vous plaisent, puis relance le reste."
                )
            ]
        , div [ A.class "days" ] (List.map (viewDay model week) (List.range 0 6))
        , div [ A.class "week-foot" ]
            [ button [ A.class "ghost", Ev.onClick ClearWeek, A.disabled rolling ] [ text "Vider la semaine" ] ]
        ]


viewDay : Model -> Week -> Int -> Html Msg
viewDay model week day =
    let
        date =
            model.monday + day
    in
    article
        [ A.class "day"
        , A.classList [ ( "today", date == model.today ), ( "weekend", day >= 5 ) ]
        , A.style "--i" (String.fromInt day)
        ]
        [ div [ A.class "day-head" ]
            [ strong [] [ text (Day.dayName day) ]
            , small [] [ text (Day.short date) ]
            , if date == model.today then
                span [ A.class "pill" ] [ text "aujourd'hui" ]

              else
                text ""
            ]
        , viewMeal model week (day * 2)
        , viewMeal model week (day * 2 + 1)
        ]


viewMeal : Model -> Week -> Int -> Html Msg
viewMeal model week slot =
    let
        meal =
            Data.mealAt slot week

        isOpen =
            model.open == Just slot

        reel =
            reelFor model slot
    in
    div
        [ A.class "meal"
        , A.classList
            [ ( "open", isOpen )
            , ( "locked", meal.locked )
            , ( "spinning", isSpinning reel )
            , ( "landed", reel == Landed )
            ]
        ]
        [ div [ A.class "meal-line" ]
            [ button
                [ A.class "meal-row"
                , Ev.onClick (Toggle slot)
                , A.attribute "aria-expanded"
                    (if isOpen then
                        "true"

                     else
                        "false"
                    )
                ]
                [ span [ A.class "moment" ]
                    [ text
                        (if Data.isSoir slot then
                            "Soir"

                         else
                            "Midi"
                        )
                    ]
                , span [ A.class "meal-body" ] (mealContent model slot meal reel)
                , span [ A.class "meal-icons" ] [ span [ A.class "chevron" ] [ text "▾" ] ]
                ]
            , case meal.choice of
                Picked _ ->
                    button
                        [ A.class "keep"
                        , A.classList [ ( "kept", meal.locked ) ]
                        , Ev.onClick (ToggleLock slot)
                        , A.disabled (isSpinning reel)
                        , A.attribute "aria-pressed"
                            (if meal.locked then
                                "true"

                             else
                                "false"
                            )
                        , A.title
                            (if meal.locked then
                                "Gardé au prochain tirage (cliquer pour libérer)"

                             else
                                "Garder ce plat au prochain tirage"
                            )
                        ]
                        [ text
                            (if meal.locked then
                                "🔒 Gardé"

                             else
                                "Garder"
                            )
                        ]

                _ ->
                    text ""
            ]
        , if isOpen then
            viewPicker model week slot meal

          else
            text ""
        ]


isSpinning : Reel -> Bool
isSpinning reel =
    case reel of
        Spinning _ ->
            True

        _ ->
            False


mealContent : Model -> Int -> Meal -> Reel -> List (Html Msg)
mealContent model slot meal reel =
    let
        boiteTag =
            if Data.feedsLeftovers slot then
                [ span [ A.class "tag boite" ] [ text ("×2 · boîte " ++ Data.feedsLabel slot) ] ]

            else
                []
    in
    case reel of
        Spinning name ->
            span [ A.class "dish" ] [ text name ] :: boiteTag

        _ ->
            case meal.choice of
                Picked dishId ->
                    span [ A.class "dish" ] [ text (dishName model dishId) ] :: boiteTag

                Leftovers ->
                    [ span [ A.class "dish leftovers" ] [ text ("🥡 " ++ leftoverName model slot) ]
                    , span [ A.class "tag" ] [ text "restes" ]
                    ]

                Free ->
                    [ span [ A.class "dish muted" ] [ text "Libre" ] ]

                Unset ->
                    span [ A.class "dish muted" ] [ text "À choisir" ] :: boiteTag


leftoverName : Model -> Int -> String
leftoverName model slot =
    let
        ( monday, source ) =
            Data.leftoverSource model.monday slot
    in
    case (Data.mealAt source (Data.weekOf monday model.state)).choice of
        Picked dishId ->
            dishName model dishId

        _ ->
            "Restes de la veille"


viewPicker : Model -> Week -> Int -> Meal -> Html Msg
viewPicker model week slot meal =
    let
        query =
            Data.normalize (String.trim model.search)

        current =
            Data.dishIdOf meal.choice

        used =
            List.range 0 13
                |> List.filter ((/=) slot)
                |> List.filterMap (\other -> Data.dishIdOf (Data.mealAt other week).choice)
                |> Set.fromList

        rec =
            recency model

        season =
            weekSeason model

        matching =
            model.state.dishes
                |> List.filter (\dish -> String.contains query (Data.normalize dish.name))
                |> List.sortBy (.name >> Data.normalize)

        -- les plats de saison d'abord
        shown =
            List.filter (Data.inSeason season) matching ++ List.filter (not << Data.inSeason season) matching
    in
    div [ A.class "picker" ]
        [ div [ A.class "chips" ]
            ([ chip (RerollOne slot) "🎲 Au hasard" False ]
                ++ (if Data.isSoir slot then
                        []

                    else
                        [ chip (SetChoice slot Leftovers) "🥡 Restes" (meal.choice == Leftovers) ]
                   )
                ++ [ chip (SetChoice slot Free) "🚫 Libre" (meal.choice == Free)
                   , chip (ToggleLock slot)
                        (if meal.locked then
                            "🔒 Verrouillé"

                         else
                            "🔓 Verrouiller"
                        )
                        meal.locked
                   ]
            )
        , case current |> Maybe.andThen (dishById model) of
            Just dish ->
                if String.isEmpty dish.url then
                    a [ A.class "recipe-link", A.href (searchUrl dish.name), A.target "_blank", A.rel "noopener" ] [ text "Chercher une recette ↗" ]

                else
                    a [ A.class "recipe-link", A.href dish.url, A.target "_blank", A.rel "noopener" ] [ text "Voir la recette ↗" ]

            Nothing ->
                text ""
        , input
            [ A.class "search"
            , A.placeholder "Chercher un plat…"
            , A.value model.search
            , Ev.onInput Search
            ]
            []
        , if List.isEmpty shown then
            p [ A.class "empty" ] [ text "Aucun plat ne correspond." ]

          else
            ul [ A.class "options" ] (List.map (viewOption season slot current used rec) shown)
        ]


chip : Msg -> String -> Bool -> Html Msg
chip msg caption active =
    button [ A.class "chip", A.classList [ ( "active", active ) ], Ev.onClick msg ] [ text caption ]


viewOption : Season -> Int -> Maybe String -> Set String -> Dict String Int -> Dish -> Html Msg
viewOption season slot current used rec dish =
    li []
        [ button
            [ A.class "option"
            , A.classList
                [ ( "current", current == Just dish.id )
                , ( "used", Set.member dish.id used )
                , ( "off-season", not (Data.inSeason season dish) )
                ]
            , Ev.onClick (SetChoice slot (Picked dish.id))
            ]
            [ span [ A.class "option-name" ] [ text dish.name ]
            , span [ A.class "option-tags" ]
                [ span [ A.class "icons", A.title (categoryTitle dish) ] [ text (categoryIcons dish) ]
                , if Set.member dish.id used then
                    span [ A.class "tag warn" ] [ text "déjà prévu" ]

                  else
                    text ""
                , recencyTag rec dish
                , if Data.inSeason season dish then
                    text ""

                  else
                    span [ A.class "tag" ] [ text ("hors saison " ++ Data.seasonsLabel dish.seasons) ]
                , if Data.feedsLeftovers slot && not dish.boite then
                    span [ A.class "tag warn" ] [ text "pas en boîte" ]

                  else
                    text ""
                ]
            ]
        ]


recencyTag : Dict String Int -> Dish -> Html msg
recencyTag rec dish =
    case Dict.get dish.id rec of
        Just offset ->
            span [ A.class "tag" ]
                [ text
                    (if offset < 0 then
                        "il y a " ++ String.fromInt (abs offset) ++ " sem."

                     else
                        "dans " ++ String.fromInt offset ++ " sem."
                    )
                ]

        Nothing ->
            text ""



-- PLATS


viewDishes : Model -> Html Msg
viewDishes model =
    let
        query =
            Data.normalize (String.trim model.dishSearch)

        rec =
            Draw.recency (Day.mondayOf model.today) model.state.weeks

        shown =
            model.state.dishes
                |> List.filter (\dish -> String.contains query (Data.normalize dish.name))
                |> List.filter (\dish -> model.seasonFilter |> Maybe.map (\season -> Data.inSeason season dish) |> Maybe.withDefault True)
                |> List.sortBy (.name >> Data.normalize)
    in
    section [ A.class "dishes" ]
        [ form [ A.class "card add-form", Ev.onSubmit AddDish ]
            [ h2 [] [ text "Ajouter un plat" ]
            , input [ A.placeholder "Nom du plat", A.value model.form.name, Ev.onInput FormName ] []
            , input [ A.placeholder "Lien de la recette (optionnel)", A.value model.form.url, Ev.onInput FormUrl ] []
            , label [ A.class "check" ]
                [ input [ A.type_ "checkbox", A.checked model.form.boite, Ev.onCheck FormBoite ] []
                , text "Se garde bien en boîte (dîner ×2)"
                ]
            , seasonPicker FormSeason model.form.seasons
            , categoryPickers FormCategory model.form
            , button [ A.class "primary", A.type_ "submit", A.disabled (String.isEmpty (String.trim model.form.name)) ] [ text "Ajouter" ]
            ]
        , input [ A.class "search", A.placeholder "Filtrer les plats…", A.value model.dishSearch, Ev.onInput DishSearch ] []
        , div [ A.class "chips" ]
            (chip (SeasonFilter Nothing) "Toutes saisons" (model.seasonFilter == Nothing)
                :: List.map
                    (\season -> chip (SeasonFilter (Just season)) (Data.seasonIcon season ++ " " ++ Data.seasonName season) (model.seasonFilter == Just season))
                    Data.allSeasons
            )
        , if List.isEmpty shown then
            p [ A.class "empty" ] [ text "Aucun plat ne correspond." ]

          else
            text ""
        , ul [ A.class "card dish-list" ] (List.map (viewDishRow model rec) shown)
        , div [ A.class "data-actions" ]
            [ button [ A.class "ghost", Ev.onClick Export ] [ text "⬇ Exporter" ]
            , button [ A.class "ghost", Ev.onClick ImportRequested ] [ text "⬆ Importer" ]
            , small [] [ text model.sync ]
            ]
        ]


viewDishRow : Model -> Dict String Int -> Dish -> Html Msg
viewDishRow model rec dish =
    case model.editing of
        Just edited ->
            if edited.id == dish.id then
                li [ A.class "dish-row editing" ]
                    [ form [ A.class "edit-form", Ev.onSubmit SaveEdit ]
                        [ input [ A.value edited.name, Ev.onInput EditName, A.placeholder "Nom du plat" ] []
                        , input [ A.value edited.url, Ev.onInput EditUrl, A.placeholder "Lien de la recette" ] []
                        , label [ A.class "check" ]
                            [ input [ A.type_ "checkbox", A.checked edited.boite, Ev.onCheck EditBoite ] []
                            , text "Se garde en boîte"
                            ]
                        , seasonPicker EditSeason edited.seasons
                        , categoryPickers EditCategory edited
                        , div [ A.class "row-actions" ]
                            [ button [ A.class "primary small", A.type_ "submit" ] [ text "Enregistrer" ]
                            , button [ A.class "ghost small", A.type_ "button", Ev.onClick CancelEdit ] [ text "Annuler" ]
                            ]
                        ]
                    ]

            else
                dishRow model rec dish

        Nothing ->
            dishRow model rec dish


dishRow : Model -> Dict String Int -> Dish -> Html Msg
dishRow model rec dish =
    li [ A.class "dish-row" ]
        [ div [ A.class "dish-info" ]
            [ strong [] [ text dish.name ]
            , span [ A.class "option-tags" ]
                [ if dish.boite then
                    span [ A.class "tag boite" ] [ text "boîte" ]

                  else
                    text ""
                , span [ A.class "tag season" ] [ text (Data.seasonsLabel dish.seasons) ]
                , categoryTags dish
                , recencyTag rec dish
                , if String.isEmpty dish.url then
                    a [ A.class "tag", A.href (searchUrl dish.name), A.target "_blank", A.rel "noopener" ] [ text "chercher ↗" ]

                  else
                    a [ A.class "tag link-tag", A.href dish.url, A.target "_blank", A.rel "noopener" ] [ text "recette ↗" ]
                ]
            ]
        , div [ A.class "row-actions" ]
            (if model.confirmDelete == Just dish.id then
                [ button [ A.class "danger small", Ev.onClick (ConfirmDelete dish.id) ] [ text "Supprimer ?" ]
                , button [ A.class "ghost small", Ev.onClick (AskDelete "") ] [ text "Non" ]
                ]

             else
                [ button [ A.class "ghost small", Ev.onClick (StartEdit dish) ] [ text "Modifier" ]
                , button [ A.class "ghost small", Ev.onClick (AskDelete dish.id), A.title "Supprimer" ] [ text "✕" ]
                ]
            )
        ]


seasonPicker : (Season -> Msg) -> List Season -> Html Msg
seasonPicker toMsg seasons =
    div [ A.class "season-picker" ]
        (span [ A.class "season-caption" ] [ text "Saisons" ]
            :: List.map
                (\season ->
                    button
                        [ A.type_ "button"
                        , A.class "chip"
                        , A.classList [ ( "active", List.member season seasons ) ]
                        , A.attribute "aria-pressed"
                            (if List.member season seasons then
                                "true"

                             else
                                "false"
                            )
                        , Ev.onClick (toMsg season)
                        ]
                        [ text (Data.seasonIcon season ++ " " ++ Data.seasonName season) ]
                )
                Data.allSeasons
        )



-- ÉQUILIBRE


categoryIcons : { r | starch : String, protein : String } -> String
categoryIcons dish =
    [ Data.categoryOf Data.starches dish.starch, Data.categoryOf Data.proteins dish.protein ]
        |> List.filterMap (Maybe.map .icon)
        |> String.concat


categoryTitle : { r | starch : String, protein : String, style : String } -> String
categoryTitle dish =
    [ Data.categoryOf Data.starches dish.starch, Data.categoryOf Data.proteins dish.protein, Data.categoryOf Data.styles dish.style ]
        |> List.filterMap (Maybe.map .label)
        |> String.join " · "


categoryTags : { r | starch : String, protein : String, style : String } -> Html msg
categoryTags dish =
    span [ A.class "option-tags" ]
        ([ Data.categoryOf Data.starches dish.starch, Data.categoryOf Data.proteins dish.protein, Data.categoryOf Data.styles dish.style ]
            |> List.filterMap identity
            |> List.map (\c -> span [ A.class "tag cat" ] [ text (c.icon ++ " " ++ c.label) ])
        )


searchUrl : String -> String
searchUrl name =
    "https://www.marmiton.org/recettes/recherche.aspx?aqt=" ++ Url.percentEncode name


categoryPickers : (Field -> String -> Msg) -> { r | starch : String, protein : String, style : String } -> Html Msg
categoryPickers toMsg dish =
    div [ A.class "category-pickers" ]
        [ categorySelect "Féculent" Data.starches dish.starch (toMsg Starch)
        , categorySelect "Protéine" Data.proteins dish.protein (toMsg Protein)
        , categorySelect "Style" Data.styles dish.style (toMsg Style)
        ]


categorySelect : String -> List Data.Category -> String -> (String -> Msg) -> Html Msg
categorySelect caption categories current toMsg =
    label [ A.class "category-select" ]
        [ span [] [ text caption ]
        , select [ Ev.onInput toMsg ]
            (option [ A.value "", A.selected (current == "") ] [ text "—" ]
                :: List.map
                    (\c -> option [ A.value c.key, A.selected (current == c.key) ] [ text (c.icon ++ " " ++ c.label) ])
                    categories
            )
        ]



-- IDÉES


viewIdeas : Model -> Html Msg
viewIdeas model =
    let
        open =
            Data.openIdeas model.state

        season =
            Data.seasonOf (model.today + 3)

        sorted =
            List.filter (\sd -> List.member season sd.seasons) open
                ++ List.filter (\sd -> not (List.member season sd.seasons)) open
    in
    section [ A.class "ideas" ]
        [ p [ A.class "hint" ]
            [ text "Des plats choisis d'après les vôtres, en priorité ceux qui varient les féculents et les protéines. Ajoutez ceux qui vous tentent : ils entrent dans le tirage." ]
        , if List.isEmpty open then
            p [ A.class "empty" ] [ text "Plus d'idée en stock pour l'instant." ]

          else
            ul [ A.class "idea-list" ] (List.map (viewIdea season) sorted)
        , if List.isEmpty model.state.dismissed then
            text ""

          else
            div [ A.class "week-foot" ]
                [ button [ A.class "ghost", Ev.onClick RestoreIdeas ]
                    [ text ("Revoir les " ++ String.fromInt (List.length model.state.dismissed) ++ " idées écartées") ]
                ]
        ]


viewIdea : Season -> Data.Seed -> Html Msg
viewIdea season sd =
    li [ A.class "card idea" ]
        [ div [ A.class "idea-head" ]
            [ strong [] [ text sd.name ]
            , if List.member season sd.seasons then
                span [ A.class "pill" ] [ text "de saison" ]

              else
                text ""
            ]
        , p [ A.class "idea-note" ] [ text sd.note ]
        , span [ A.class "option-tags" ]
            [ span [ A.class "tag season" ] [ text (Data.seasonsLabel sd.seasons) ]
            , categoryTags sd
            , if sd.boite then
                span [ A.class "tag boite" ] [ text "boîte" ]

              else
                text ""
            ]
        , div [ A.class "row-actions" ]
            [ button [ A.class "primary small", Ev.onClick (AdoptIdea sd.name) ] [ text "+ Ajouter à nos plats" ]
            , a [ A.class "ghost small", A.href (searchUrl sd.name), A.target "_blank", A.rel "noopener" ] [ text "Trouver une recette ↗" ]
            , button [ A.class "ghost small", Ev.onClick (DismissIdea sd.name) ] [ text "Pas pour nous" ]
            ]
        ]
