module Day exposing (dayName, mondayOf, month, short, weekLabel, weekday)

{-| Jours exprimés en nombre de jours depuis le 1970-01-01 (un jeudi).
-}


{-| 0 = lundi … 6 = dimanche
-}
weekday : Int -> Int
weekday d =
    modBy 7 (d + 3)


mondayOf : Int -> Int
mondayOf d =
    d - weekday d


dayName : Int -> String
dayName i =
    case i of
        0 ->
            "Lundi"

        1 ->
            "Mardi"

        2 ->
            "Mercredi"

        3 ->
            "Jeudi"

        4 ->
            "Vendredi"

        5 ->
            "Samedi"

        _ ->
            "Dimanche"


type alias Civil =
    { year : Int, month : Int, day : Int }


{-| Algorithme « days from civil » inversé (H. Hinnant), valable après 1970.
-}
civil : Int -> Civil
civil z0 =
    let
        z =
            z0 + 719468

        era =
            z // 146097

        doe =
            z - era * 146097

        yoe =
            (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365

        doy =
            doe - (365 * yoe + yoe // 4 - yoe // 100)

        mp =
            (5 * doy + 2) // 153

        d =
            doy - (153 * mp + 2) // 5 + 1

        m =
            if mp < 10 then
                mp + 3

            else
                mp - 9

        y =
            yoe + era * 400
    in
    { year =
        if m <= 2 then
            y + 1

        else
            y
    , month = m
    , day = d
    }


month : Int -> Int
month d =
    (civil d).month


monthName : Int -> String
monthName m =
    case m of
        1 ->
            "janv."

        2 ->
            "févr."

        3 ->
            "mars"

        4 ->
            "avr."

        5 ->
            "mai"

        6 ->
            "juin"

        7 ->
            "juil."

        8 ->
            "août"

        9 ->
            "sept."

        10 ->
            "oct."

        11 ->
            "nov."

        _ ->
            "déc."


{-| « 16 nov. »
-}
short : Int -> String
short d =
    let
        c =
            civil d
    in
    String.fromInt c.day ++ " " ++ monthName c.month


{-| « 16 – 22 nov. » ou « 30 nov. – 6 déc. »
-}
weekLabel : Int -> String
weekLabel monday =
    let
        a =
            civil monday

        b =
            civil (monday + 6)
    in
    if a.month == b.month then
        String.fromInt a.day ++ " – " ++ short (monday + 6)

    else
        short monday ++ " – " ++ short (monday + 6)
