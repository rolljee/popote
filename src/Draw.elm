module Draw exposing (pick, pickMany, recency)

{-| Tirage au sort : plats de saison, pas de doublon dans la semaine, les plats
mangés récemment (± 4 semaines) ont moins de chances de sortir, et la semaine
s'équilibre : chaque féculent, protéine ou style déjà tiré rend les plats qui
le partagent nettement moins probables.
-}

import Data exposing (Dish, Season, Week)
import Dict exposing (Dict)
import Random exposing (Generator)
import Set exposing (Set)


{-| Pour chaque plat, l'écart en semaines (signé, non nul) avec la semaine la
plus proche où il apparaît, dans une fenêtre de 4 semaines.
-}
recency : Int -> Dict Int Week -> Dict String Int
recency monday weeks =
    Dict.foldl
        (\other week acc ->
            let
                offset =
                    (other - monday) // 7
            in
            if other == monday || abs offset > 4 then
                acc

            else
                Dict.foldl
                    (\_ meal inner ->
                        case Data.dishIdOf meal.choice of
                            Just dishId ->
                                case Dict.get dishId inner of
                                    Just known ->
                                        if abs known <= abs offset then
                                            inner

                                        else
                                            Dict.insert dishId offset inner

                                    Nothing ->
                                        Dict.insert dishId offset inner

                            Nothing ->
                                inner
                    )
                    acc
                    week
        )
        Dict.empty
        weeks


weight : Dict String Int -> Dish -> Float
weight rec dish =
    case Dict.get dish.id rec |> Maybe.map abs of
        Just 1 ->
            1

        Just 2 ->
            4

        Just 3 ->
            8

        _ ->
            12


{-| Par ordre de préférence : de saison, pas encore prévu, compatible boîte.
On relâche d'abord la boîte, puis la saison, puis les doublons.
-}
pick : Season -> List Dish -> Dict String Int -> Set String -> Bool -> Generator (Maybe String)
pick season dishes rec used needBoite =
    let
        chosen =
            List.filter (\dish -> Set.member dish.id used) dishes

        repeats field factor dish =
            if String.isEmpty (field dish) then
                1

            else
                factor ^ toFloat (List.length (List.filter (\other -> field other == field dish) chosen))

        score dish =
            weight rec dish * repeats .starch 0.15 dish * repeats .protein 0.2 dish * repeats .style 0.35 dish

        fresh =
            List.filter (\dish -> not (Set.member dish.id used)) dishes

        seasonal =
            List.filter (Data.inSeason season) fresh

        boiteOk =
            List.filter (\dish -> dish.boite || not needBoite)

        pool =
            [ boiteOk seasonal
            , seasonal
            , boiteOk fresh
            , fresh
            , dishes
            ]
                |> List.filter (not << List.isEmpty)
                |> List.head
                |> Maybe.withDefault []
    in
    case pool of
        [] ->
            Random.constant Nothing

        first :: rest ->
            Random.weighted ( score first, first ) (List.map (\dish -> ( score dish, dish )) rest)
                |> Random.map (.id >> Just)


{-| `slots` : (créneau, doit se garder en boîte). Les créneaux « boîte » passent
en premier pour ne pas épuiser les plats compatibles.
-}
pickMany : Season -> List Dish -> Dict String Int -> Set String -> List ( Int, Bool ) -> Generator (List ( Int, String ))
pickMany season dishes rec used slots =
    let
        go taken remaining =
            case remaining of
                [] ->
                    Random.constant []

                ( slot, needBoite ) :: rest ->
                    pick season dishes rec taken needBoite
                        |> Random.andThen
                            (\picked ->
                                case picked of
                                    Just dishId ->
                                        go (Set.insert dishId taken) rest |> Random.map ((::) ( slot, dishId ))

                                    Nothing ->
                                        go taken rest
                            )
    in
    go used
        (List.sortBy
            (\( _, needBoite ) ->
                if needBoite then
                    0

                else
                    1
            )
            slots
        )
