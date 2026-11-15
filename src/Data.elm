module Data exposing
    ( Category
    , Choice(..)
    , Dish
    , Meal
    , Season(..)
    , Seed
    , State
    , Week
    , allSeasons
    , categoryOf
    , decoder
    , dishIdOf
    , emptyWeek
    , encode
    , feedsLabel
    , feedsLeftovers
    , ideas
    , inSeason
    , initial
    , isLeftoverLunch
    , isSoir
    , leftoverSource
    , mealAt
    , normalize
    , openIdeas
    , proteins
    , seasonIcon
    , seasonName
    , seasonOf
    , seasonsLabel
    , starches
    , styles
    , toDish
    , toggleSeason
    , uniqueId
    , weekOf
    )

{-| Plats, semaines et règles du foyer.

Une semaine compte 14 créneaux : `jour * 2` pour le midi, `jour * 2 + 1` pour
le soir (jour 0 = lundi). Les dîners du dimanche, lundi et mercredi se cuisinent
en double : le reste part en boîte pour le midi du lendemain (lundi, mardi,
jeudi).

-}

import Day
import Dict exposing (Dict)
import Json.Decode as D
import Json.Encode as E
import Set



-- MODÈLE


type alias Dish =
    { id : String
    , name : String
    , url : String
    , boite : Bool
    , seasons : List Season
    , starch : String
    , protein : String
    , style : String
    }


type Season
    = Printemps
    | Ete
    | Automne
    | Hiver


type Choice
    = Picked String
    | Leftovers
    | Free
    | Unset


type alias Meal =
    { choice : Choice
    , locked : Bool
    }


type alias Week =
    Dict Int Meal


{-| `weeks` est indexé par le lundi (nombre de jours depuis 1970).
-}
type alias State =
    { dishes : List Dish
    , weeks : Dict Int Week
    , seeded : Int
    , dismissed : List String
    }



-- SAISONS


allSeasons : List Season
allSeasons =
    [ Printemps, Ete, Automne, Hiver ]


{-| Saison météorologique du jour donné (on prend le jeudi d'une semaine).
-}
seasonOf : Int -> Season
seasonOf day =
    let
        month =
            Day.month day
    in
    if month >= 3 && month <= 5 then
        Printemps

    else if month >= 6 && month <= 8 then
        Ete

    else if month >= 9 && month <= 11 then
        Automne

    else
        Hiver


inSeason : Season -> Dish -> Bool
inSeason season dish =
    List.member season dish.seasons


seasonName : Season -> String
seasonName season =
    case season of
        Printemps ->
            "Printemps"

        Ete ->
            "Été"

        Automne ->
            "Automne"

        Hiver ->
            "Hiver"


seasonIcon : Season -> String
seasonIcon season =
    case season of
        Printemps ->
            "🌸"

        Ete ->
            "☀️"

        Automne ->
            "🍂"

        Hiver ->
            "❄️"


seasonsLabel : List Season -> String
seasonsLabel seasons =
    if List.length seasons == 4 then
        "toute l'année"

    else
        String.join " " (List.map seasonIcon seasons)


{-| Garde l'ordre de l'année.
-}
toggleSeason : Season -> List Season -> List Season
toggleSeason season seasons =
    List.filter
        (\s ->
            if s == season then
                not (List.member s seasons)

            else
                List.member s seasons
        )
        allSeasons



-- RÈGLES DU FOYER


isSoir : Int -> Bool
isSoir slot =
    modBy 2 slot == 1


{-| Midis en boîte : lundi, mardi, jeudi.
-}
isLeftoverLunch : Int -> Bool
isLeftoverLunch slot =
    not (isSoir slot) && List.member (slot // 2) [ 0, 1, 3 ]


{-| Dîners cuisinés en double : dimanche, lundi, mercredi.
-}
feedsLeftovers : Int -> Bool
feedsLeftovers slot =
    isSoir slot && List.member (slot // 2) [ 6, 0, 2 ]


feedsLabel : Int -> String
feedsLabel slot =
    case slot // 2 of
        6 ->
            "lundi"

        0 ->
            "mardi"

        _ ->
            "jeudi"


{-| Le dîner qui remplit la boîte d'un midi : (lundi de sa semaine, créneau).
Le lundi midi mange les restes du dimanche soir de la semaine précédente.
-}
leftoverSource : Int -> Int -> ( Int, Int )
leftoverSource monday slot =
    let
        day =
            slot // 2
    in
    if day == 0 then
        ( monday - 7, 13 )

    else
        ( monday, (day - 1) * 2 + 1 )


defaultChoice : Int -> Choice
defaultChoice slot =
    if isLeftoverLunch slot then
        Leftovers

    else
        Unset


emptyWeek : Week
emptyWeek =
    List.range 0 13
        |> List.map (\slot -> ( slot, { choice = defaultChoice slot, locked = False } ))
        |> Dict.fromList


weekOf : Int -> State -> Week
weekOf monday state =
    Dict.get monday state.weeks |> Maybe.withDefault emptyWeek


mealAt : Int -> Week -> Meal
mealAt slot week =
    Dict.get slot week |> Maybe.withDefault { choice = defaultChoice slot, locked = False }


dishIdOf : Choice -> Maybe String
dishIdOf choice =
    case choice of
        Picked dishId ->
            Just dishId

        _ ->
            Nothing



-- IDENTIFIANTS


normalize : String -> String
normalize =
    String.toLower
        >> String.map
            (\c ->
                case c of
                    'é' ->
                        'e'

                    'è' ->
                        'e'

                    'ê' ->
                        'e'

                    'ë' ->
                        'e'

                    'à' ->
                        'a'

                    'â' ->
                        'a'

                    'î' ->
                        'i'

                    'ï' ->
                        'i'

                    'ô' ->
                        'o'

                    'ö' ->
                        'o'

                    'ù' ->
                        'u'

                    'û' ->
                        'u'

                    'ü' ->
                        'u'

                    'ç' ->
                        'c'

                    _ ->
                        c
            )


uniqueId : String -> List Dish -> String
uniqueId name dishes =
    let
        slug =
            normalize name
                |> String.map
                    (\c ->
                        if Char.isAlphaNum c then
                            c

                        else
                            '-'
                    )

        base =
            if String.isEmpty slug then
                "plat"

            else
                slug

        taken =
            List.map .id dishes |> Set.fromList

        go n =
            let
                candidate =
                    if n == 1 then
                        base

                    else
                        base ++ "-" ++ String.fromInt n
            in
            if Set.member candidate taken then
                go (n + 1)

            else
                candidate
    in
    go 1



-- CATÉGORIES (équilibre de la semaine)


type alias Category =
    { key : String, label : String, icon : String }


starches : List Category
starches =
    [ Category "pates" "Pâtes" "🍝"
    , Category "riz" "Riz" "🍚"
    , Category "pdt" "Pommes de terre" "🥔"
    , Category "gnocchis" "Gnocchis" "🥟"
    , Category "cereales" "Céréales (quinoa, blé, semoule…)" "🌾"
    , Category "legumineuses" "Légumineuses" "🫘"
    , Category "pate" "Pâte & pain" "🥧"
    , Category "aucun" "Sans féculent" "🥦"
    ]


proteins : List Category
proteins =
    [ Category "boeuf" "Bœuf & veau" "🐄"
    , Category "porc" "Porc & charcuterie" "🐖"
    , Category "volaille" "Volaille & lapin" "🐔"
    , Category "poisson" "Poisson" "🐟"
    , Category "mer" "Fruits de mer" "🦐"
    , Category "oeuf-fromage" "Œufs & fromage" "🧀"
    , Category "vege" "Végétal" "🌱"
    ]


styles : List Category
styles =
    [ Category "gratin" "Gratin & four" "🔥"
    , Category "quiche" "Quiche & tarte" "🥧"
    , Category "soupe" "Soupe" "🍲"
    , Category "salade" "Salade" "🥗"
    , Category "mijote" "Mijoté & curry" "🫕"
    , Category "poele" "Poêlée & one-pot" "🍳"
    , Category "simple" "Assiette simple" "🍽️"
    , Category "convivial" "Convivial" "🧑\u{200D}🍳"
    ]


categoryOf : List Category -> String -> Maybe Category
categoryOf list key =
    List.filter (\c -> c.key == key) list |> List.head



-- PLATS DE DÉPART


{-| À incrémenter quand on ajoute des plats à `seeds` : ils sont alors ajoutés
aux données existantes au prochain chargement.
-}
seedVersion : Int
seedVersion =
    2


type alias Seed =
    { version : Int
    , name : String
    , url : String
    , boite : Bool
    , seasons : List Season
    , starch : String
    , protein : String
    , style : String
    , note : String
    }


toDish : List Dish -> Seed -> Dish
toDish dishes sd =
    { id = uniqueId sd.name dishes
    , name = sd.name
    , url = sd.url
    , boite = sd.boite
    , seasons = sd.seasons
    , starch = sd.starch
    , protein = sd.protein
    , style = sd.style
    }


initial : State
initial =
    { dishes = addSeeds (always True) seeds []
    , weeks = Dict.empty
    , seeded = seedVersion
    , dismissed = []
    }


addSeeds : (Seed -> Bool) -> List Seed -> List Dish -> List Dish
addSeeds keep list dishes =
    List.foldl
        (\sd acc ->
            if keep sd && not (List.any (\d -> normalize d.name == normalize sd.name) acc) then
                acc ++ [ toDish acc sd ]

            else
                acc
        )
        dishes
        list


{-| Ajoute les plats de départ apparus depuis la dernière visite.
-}
migrate : State -> State
migrate state =
    if state.seeded >= seedVersion then
        state

    else
        { state
            | dishes = addSeeds (\sd -> sd.version > state.seeded) seeds state.dishes
            , seeded = seedVersion
        }


{-| Le plat de départ (ou l'idée) du même nom : sert à compléter les champs
absents des données enregistrées avant leur apparition.
-}
seedFor : String -> Maybe Seed
seedFor name =
    (seeds ++ ideas)
        |> List.filter (\sd -> normalize sd.name == normalize name)
        |> List.head


defaultSeasons : String -> List Season
defaultSeasons name =
    seedFor name |> Maybe.map .seasons |> Maybe.withDefault allSeasons


all : List Season
all =
    allSeasons


warm : List Season
warm =
    [ Printemps, Ete ]


cold : List Season
cold =
    [ Automne, Hiver ]


seed : Int -> String -> String -> Bool -> List Season -> String -> String -> String -> Seed
seed version name url boite seasons starch protein style =
    Seed version name url boite seasons starch protein style ""


seeds : List Seed
seeds =
    [ seed 1 "Spaghetti crevettes tomates cerises" "https://www.taste.com.au/recipes/one-pot-sweet-chilli-prawn-pasta-recipe/yicujbn3" True warm "pates" "mer" "poele"
    , seed 1 "Gnocchi pesto petits pois" "https://www.taste.com.au/recipes/gnocchi-pesto-peas/c779d482-a5a3-443c-b7b3-8df897a736bb" True warm "gnocchis" "vege" "poele"
    , seed 1 "Lapin aux pruneaux & polenta" "" True cold "cereales" "volaille" "mijote"
    , seed 1 "Quinoa pesto légumes" "https://www.lesrecettesdecaty.com/fr/recettes/casserole-de-quinoa-au-pesto-et-aux-legumes/" True [ Printemps, Ete, Automne ] "cereales" "vege" "gratin"
    , seed 1 "Jambalaya" "https://www.elle.fr/Elle-a-Table/Recettes-de-cuisine/Jambalaya-2028232" True all "riz" "volaille" "mijote"
    , seed 1 "Gratin dauphinois" "" True cold "pdt" "oeuf-fromage" "gratin"
    , seed 1 "Raclette" "" False [ Hiver ] "pdt" "porc" "convivial"
    , seed 1 "Pâtes feta" "" True warm "pates" "oeuf-fromage" "gratin"
    , seed 1 "Saucisses lentilles" "" True cold "legumineuses" "porc" "mijote"
    , seed 1 "Soupe butternut châtaigne" "" True cold "aucun" "vege" "soupe"
    , seed 1 "Gratin de chou-fleur" "" True cold "aucun" "oeuf-fromage" "gratin"
    , seed 1 "Gratin chou-fleur lardons" "" True cold "aucun" "porc" "gratin"
    , seed 1 "Gratin pommes de terre chou-fleur" "" True cold "pdt" "oeuf-fromage" "gratin"
    , seed 1 "Quiche saumon poireaux" "" True [ Printemps, Automne, Hiver ] "pate" "poisson" "quiche"
    , seed 1 "Quiche jambon" "" True all "pate" "porc" "quiche"
    , seed 1 "Quiche lorraine" "" True all "pate" "porc" "quiche"
    , seed 1 "Steak pommes de terre haricots" "" False all "pdt" "boeuf" "simple"
    , seed 1 "Coquilloto" "" True all "pates" "porc" "poele"
    , seed 1 "Paella" "" True warm "riz" "mer" "mijote"
    , seed 1 "Poulet au curry" "" True all "riz" "volaille" "mijote"
    , seed 1 "Endives au jambon" "" True cold "aucun" "porc" "gratin"
    , seed 1 "Parmentier de canard (Jow)" "" True cold "pdt" "volaille" "gratin"
    , seed 1 "Gratin gnocchis mozzarella (Jow)" "" True cold "gnocchis" "oeuf-fromage" "gratin"
    , seed 1 "Salade pommes de terre saumon (Jow)" "" True warm "pdt" "poisson" "salade"
    , seed 1 "Poisson épinards" "" True all "aucun" "poisson" "simple"
    , seed 1 "Salade poulet blé pesto (Jow)" "" True warm "cereales" "volaille" "salade"
    , seed 1 "Salade lentilles haricots" "" True warm "legumineuses" "vege" "salade"
    , seed 1 "Riz brocolis poisson" "" True all "riz" "poisson" "simple"
    , seed 1 "Pâtes courgettes viande" "" True warm "pates" "boeuf" "poele"
    , seed 1 "Salade piémontaise" "" True warm "pdt" "porc" "salade"
    , seed 1 "Bœuf bourguignon" "" True cold "pdt" "boeuf" "mijote"
    , seed 1 "Pâtes butternut" "" True cold "pates" "vege" "poele"
    , seed 2 "Quiche aux épinards" "" True all "pate" "oeuf-fromage" "quiche"
    , seed 2 "Pâtes bolognaise" "" True all "pates" "boeuf" "mijote"
    , seed 2 "Pâtes carbonara" "" True all "pates" "porc" "poele"
    , seed 2 "Pâtes sauce courgette" "" True warm "pates" "vege" "poele"
    , seed 2 "Gnocchi poêlés légumes verts pesto" "" True warm "gnocchis" "vege" "poele"
    ]



-- IDÉES À ESSAYER


idea : String -> String -> Bool -> List Season -> String -> String -> String -> Seed
idea name note boite seasons starch protein style =
    Seed 0 name "" boite seasons starch protein style note


{-| Choisies d'après les plats du foyer : familiales, faciles à réchauffer,
et qui élargissent les féculents et protéines peu présents (riz, céréales,
légumineuses, bœuf, poisson).
-}
ideas : List Seed
ideas =
    [ idea "Hachis parmentier" "Le cousin du parmentier de canard, au bœuf : un succès chez les petits." True cold "pdt" "boeuf" "gratin"
    , idea "Lasagnes bolognaise" "Pour ceux qui aiment la bolo : se prépare à l'avance et se réchauffe très bien." True all "pates" "boeuf" "gratin"
    , idea "Risotto butternut parmesan" "Dans la lignée des pâtes butternut, en version crémeuse au riz." True cold "riz" "oeuf-fromage" "mijote"
    , idea "Dahl de lentilles corail coco" "Doux et réconfortant comme le curry, 100 % végétal, avec du riz." True all "legumineuses" "vege" "mijote"
    , idea "Chili con carne" "Bœuf, haricots rouges et riz : idéal en boîte le lendemain." True cold "riz" "boeuf" "mijote"
    , idea "Blanquette de veau" "Un mijoté doux qui change du bourguignon, avec du riz." True cold "riz" "boeuf" "mijote"
    , idea "Poulet basquaise & riz" "Poivrons et tomates : le pendant estival du poulet au curry." True [ Ete, Automne ] "riz" "volaille" "mijote"
    , idea "Couscous poulet légumes" "Semoule et légumes fondants : tout le monde pioche ce qu'il aime." True [ Printemps, Automne, Hiver ] "cereales" "volaille" "mijote"
    , idea "Poulet rôti & pommes de terre grenaille" "Le classique du dimanche soir, parfait pour la boîte du lundi." True all "pdt" "volaille" "gratin"
    , idea "Brandade de morue" "Un gratin de poisson que les enfants mangent sans s'en rendre compte." True cold "pdt" "poisson" "gratin"
    , idea "Pâtes saumon épinards à la crème" "Le duo de la quiche saumon et du poisson épinards, en version rapide." True all "pates" "poisson" "poele"
    , idea "Saumon en papillote, quinoa & haricots verts" "Léger, vite prêt, et le quinoa change du riz." True [ Printemps, Ete ] "cereales" "poisson" "simple"
    , idea "Tartiflette" "Pour les soirs d'hiver entre deux raclettes." True [ Hiver ] "pdt" "porc" "gratin"
    , idea "Croziflette" "Les crozets façon tartiflette : pâtes, lardons, reblochon." True [ Hiver ] "pates" "porc" "gratin"
    , idea "Porc au caramel & riz" "Sucré-salé doux, très apprécié des enfants." True all "riz" "porc" "mijote"
    , idea "Wok de nouilles poulet légumes" "Poêlée express, les légumes de saison passent tout seuls." True all "pates" "volaille" "poele"
    , idea "Taboulé au poulet" "Salade fraîche de semoule pour les midis d'été." True [ Ete ] "cereales" "volaille" "salade"
    , idea "Salade de pâtes grecque" "Feta, concombre, tomates, olives : l'esprit des pâtes feta, en froid." True [ Ete ] "pates" "oeuf-fromage" "salade"
    , idea "Ratatouille, riz & œuf au plat" "Le plat végétarien de l'été, encore meilleur réchauffé." True [ Ete, Automne ] "riz" "oeuf-fromage" "mijote"
    , idea "Moussaka" "Gratin d'aubergines et bœuf, à faire la veille." True [ Ete, Automne ] "pdt" "boeuf" "gratin"
    , idea "Minestrone" "Soupe complète aux petites pâtes et haricots blancs." True [ Printemps, Automne ] "pates" "vege" "soupe"
    , idea "Velouté de potimarron & croûtons au fromage" "Pour varier la soupe butternut châtaigne." True cold "aucun" "oeuf-fromage" "soupe"
    , idea "Galettes de sarrasin complètes" "Jambon, œuf, fromage : chacun garnit la sienne." False all "pate" "porc" "convivial"
    , idea "Pizza maison" "À garnir en famille, la grande peut aider." False all "pate" "oeuf-fromage" "convivial"
    , idea "Gratin de pâtes jambon brocolis" "Un gratin complet qui fait passer le brocoli." True cold "pates" "porc" "gratin"
    , idea "Curry de pois chiches épinards" "Végétal et rassasiant, avec du riz ou du naan." True all "legumineuses" "vege" "mijote"
    , idea "Petit salé aux lentilles" "Le grand frère des saucisses lentilles." True [ Hiver ] "legumineuses" "porc" "mijote"
    , idea "Cabillaud, purée de carottes" "Poisson blanc tout doux, adapté au bébé en version mixée." True all "pdt" "poisson" "simple"
    ]


{-| Idées pas encore au menu ni écartées.
-}
openIdeas : State -> List Seed
openIdeas state =
    List.filter
        (\sd ->
            not (List.any (\d -> normalize d.name == normalize sd.name) state.dishes)
                && not (List.member (normalize sd.name) state.dismissed)
        )
        ideas



-- JSON


encode : State -> E.Value
encode state =
    E.object
        [ ( "version", E.int 3 )
        , ( "dismissed", E.list E.string state.dismissed )
        , ( "seeded", E.int state.seeded )
        , ( "dishes", E.list encodeDish state.dishes )
        , ( "weeks"
          , E.list
                (\( monday, week ) ->
                    E.object
                        [ ( "monday", E.int monday )
                        , ( "meals", E.list encodeMeal (Dict.toList week) )
                        ]
                )
                (Dict.toList state.weeks)
          )
        ]


encodeDish : Dish -> E.Value
encodeDish dish =
    E.object
        [ ( "id", E.string dish.id )
        , ( "name", E.string dish.name )
        , ( "url", E.string dish.url )
        , ( "boite", E.bool dish.boite )
        , ( "seasons", E.list (seasonKey >> E.string) dish.seasons )
        , ( "starch", E.string dish.starch )
        , ( "protein", E.string dish.protein )
        , ( "style", E.string dish.style )
        ]


seasonKey : Season -> String
seasonKey season =
    case season of
        Printemps ->
            "printemps"

        Ete ->
            "ete"

        Automne ->
            "automne"

        Hiver ->
            "hiver"


seasonFromKey : String -> Maybe Season
seasonFromKey key =
    List.filter (\season -> seasonKey season == key) allSeasons |> List.head


encodeMeal : ( Int, Meal ) -> E.Value
encodeMeal ( slot, meal ) =
    E.object
        ([ ( "slot", E.int slot ), ( "locked", E.bool meal.locked ) ]
            ++ (case meal.choice of
                    Picked dishId ->
                        [ ( "kind", E.string "dish" ), ( "dish", E.string dishId ) ]

                    Leftovers ->
                        [ ( "kind", E.string "leftovers" ) ]

                    Free ->
                        [ ( "kind", E.string "free" ) ]

                    Unset ->
                        [ ( "kind", E.string "unset" ) ]
               )
        )


decoder : D.Decoder State
decoder =
    D.map4 State
        (D.field "dishes" (D.list dishDecoder))
        (D.field "weeks" (D.list weekDecoder) |> D.map Dict.fromList)
        (D.oneOf [ D.field "seeded" D.int, D.succeed 1 ])
        (D.oneOf [ D.field "dismissed" (D.list D.string), D.succeed [] ])
        |> D.map migrate


dishDecoder : D.Decoder Dish
dishDecoder =
    D.field "name" D.string
        |> D.andThen
            (\name ->
                let
                    fromSeed field =
                        D.oneOf [ D.field field D.string, D.succeed (seedField field name) ]
                in
                D.map7 (\dishId -> Dish dishId name)
                    (D.field "id" D.string)
                    (D.oneOf [ D.field "url" D.string, D.succeed "" ])
                    (D.oneOf [ D.field "boite" D.bool, D.succeed True ])
                    (D.oneOf [ D.field "seasons" (D.list D.string |> D.map (List.filterMap seasonFromKey)), D.succeed [] ]
                        |> D.map (fillSeasons name)
                    )
                    (fromSeed "starch")
                    (fromSeed "protein")
                    (fromSeed "style")
            )


{-| Catégorie absente (données d'avant l'équilibrage) : celle du plat de départ
du même nom, sinon non renseignée.
-}
seedField : String -> String -> String
seedField field name =
    case seedFor name of
        Just sd ->
            case field of
                "starch" ->
                    sd.starch

                "protein" ->
                    sd.protein

                _ ->
                    sd.style

        Nothing ->
            ""


{-| Sans saison connue (données d'avant les saisons) : celles du plat de départ
du même nom, sinon toute l'année.
-}
fillSeasons : String -> List Season -> List Season
fillSeasons name seasons =
    if List.isEmpty seasons then
        defaultSeasons name

    else
        seasons


weekDecoder : D.Decoder ( Int, Week )
weekDecoder =
    D.map2 Tuple.pair
        (D.field "monday" D.int)
        (D.field "meals" (D.list mealDecoder)
            |> D.map (List.foldl (\( slot, meal ) week -> Dict.insert slot meal week) emptyWeek)
        )


mealDecoder : D.Decoder ( Int, Meal )
mealDecoder =
    D.map3 (\slot choice locked -> ( slot, { choice = choice, locked = locked } ))
        (D.field "slot" D.int)
        (D.field "kind" D.string |> D.andThen choiceDecoder)
        (D.oneOf [ D.field "locked" D.bool, D.succeed False ])


choiceDecoder : String -> D.Decoder Choice
choiceDecoder kind =
    case kind of
        "dish" ->
            D.field "dish" D.string |> D.map Picked

        "leftovers" ->
            D.succeed Leftovers

        "free" ->
            D.succeed Free

        _ ->
            D.succeed Unset
