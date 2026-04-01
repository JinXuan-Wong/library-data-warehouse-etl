CREATE OR REPLACE PROCEDURE populate_booktitles_9k(
  p_target_count IN PLS_INTEGER DEFAULT 9000
) IS
  /* ==============================
     CONFIG: EDIT GENRES TO MATCH YOUR FILE
     ============================== */
  TYPE t_genres IS TABLE OF VARCHAR2(100);
  v_genres t_genres := t_genres(
    -- Put EXACT spellings/casing present in your SQL file:
    'Fantasy','Fiction','Mystery','Adventure','Romance',
    'Non Fiction','Thriller','History','Juvenile Fiction',
    'Philosophy','Autobiography','Non fiction','HIstory','Nonfiction'
  );

  /* ==============================
     WORD BANKS FOR UNIQUE TITLES (no digits)
     (30 x 30 x 30 = 27,000+ unique combos)
     ============================== */
  TYPE t_words IS TABLE OF VARCHAR2(40);
  v_adjs t_words := t_words(
    'Hidden','Crimson','Silver','Lost','Eternal','Silent','Wandering','Bright','Fallen','Verdant',
    'Midnight','Golden','Shattered','Sacred','Broken','Secret','Burning','Ivory','Emerald','Scarlet',
    'Azure','Veiled','Forgotten','Gilded','Hollow','Radiant','Lone','Whispering','Stormbound','Ancient'
  );
  v_nouns t_words := t_words(
    'Empire','River','Garden','Chronicle','Legacy','Promise','Labyrinth','Echo','Voyage','Harbor',
    'Covenant','Paradox','Mirage','Beacon','Citadel','Odyssey','Canvas','Whisper','Archive','Verse',
    'Valley','Kingdom','Forest','Tide','Sanctum','Throne','Bloom','Frontier','Spire','Horizon'
  );
  v_themes t_words := t_words(
    'Shadows','Dreams','Stars','Ashes','Winds','Secrets','Paths','Embers','Tides','Silence',
    'Fates','Echoes','Memories','Storms','Fields','Wonders','Visions','Origins','Reflections','Ruins',
    'Waves','Voices','Promises','Skies','Leaves','Riddles','Harbors','Oaths','Songs','Stories'
  );

  /* ==============================
     NAME BANKS FOR HUMAN AUTHORS
     ============================== */
  TYPE t_names IS TABLE OF VARCHAR2(40);
  v_first t_names := t_names(
    'Aisha','Akira','Amelia','Arun','Bao','Camila','Charles','Danial','Dewi','Elena',
    'Ethan','Fatimah','Gabriel','Hiro','Isabella','Jae','Jamal','Juan','Kai','Kamala',
    'Laila','Li','Maria','Maya','Muhammad','Noah','Nurul','Olivia','Omar','Priya',
    'Qin','Rafi','Reina','Sara','Siti','Sofia','Takahiro','Thabo','Wei','Yusuf'
  );
  v_last  t_names := t_names(
    'Abdullah','Ahmad','Ali','Ariff','Bautista','Chen','Garcia','Hernandez','Hidayat','Ibrahim',
    'Iskandar','Johnson','Kawamura','Khan','Kobayashi','Kumar','Lee','Lim','Martinez','Matsumoto',
    'Nguyen','Ong','Perez','Rahman','Rodríguez','Tan','Wang','Wei','Yamamoto','Zhang',
    'Zulkifli','Sato','Hashim','Othman','Fernandez','Silva','Singh','Putra','Halim','Hashimoto'
  );

  v_inserted   PLS_INTEGER := 0;
  v_try_num    PLS_INTEGER := 1;   -- numeric part for B0001...
  v_id         VARCHAR2(20);
  v_title      VARCHAR2(255);
  v_author     VARCHAR2(255);
  v_genre      VARCHAR2(100);
  v_year       NUMBER(4);
  v_sales      NUMBER(6,2);
  v_purchase   NUMBER(6,2);
  v_pop        NUMBER(2,1);

  /* Map an index -> unique, human-friendly title (no numbers) */
  FUNCTION make_unique_title(i IN PLS_INTEGER) RETURN VARCHAR2 IS
    a_idx PLS_INTEGER := MOD(i, v_adjs.COUNT); -- 0..COUNT-1
    n_idx PLS_INTEGER := MOD(TRUNC(i / v_adjs.COUNT), v_nouns.COUNT);
    t_idx PLS_INTEGER := MOD(TRUNC(i / (v_adjs.COUNT * v_nouns.COUNT)), v_themes.COUNT);
  BEGIN
    RETURN v_adjs(a_idx + 1) || ' ' || v_nouns(n_idx + 1) || ' of ' || v_themes(t_idx + 1);
  END;

  /* Ensure ID B0001..B9999 style and skip if exists */
  FUNCTION next_free_id(start_from IN PLS_INTEGER) RETURN VARCHAR2 IS
    n   PLS_INTEGER := start_from;
    id5 VARCHAR2(20);
    c   PLS_INTEGER;
  BEGIN
    LOOP
      id5 := 'B' || LPAD(TO_CHAR(n), 4, '0');  -- B0001..B9999
      SELECT COUNT(*) INTO c FROM BookTitles WHERE bookId = id5;
      EXIT WHEN c = 0;
      n := n + 1;
      IF n > 99999 THEN
        RAISE_APPLICATION_ERROR(-20002, 'Ran out of Bnnnnn IDs.');
      END IF;
    END LOOP;
    RETURN id5;
  END;

BEGIN
  DBMS_OUTPUT.PUT_LINE('Starting insert... target=' || p_target_count);

  WHILE v_inserted < p_target_count LOOP
    /* ID */
    v_id := next_free_id(v_try_num);
    v_try_num := TO_NUMBER(SUBSTR(v_id, 2)) + 1; -- strip 'B'

    /* Title: deterministic, digit-free, unique by construction; still double-check table */
    v_title := make_unique_title(v_inserted);

    /* If (very unlikely) exists already, perturb by rotating words */
    DECLARE c INTEGER; BEGIN
      SELECT COUNT(*) INTO c FROM BookTitles WHERE LOWER(title) = LOWER(v_title);
      IF c > 0 THEN
        -- rotate components to keep it readable and still no digits
        v_title := REPLACE(v_title, ' of ', ' and ');
      END IF;
    END;

    /* Author: First + Last (human names) */
    v_author := v_first( MOD(v_inserted, v_first.COUNT) + 1 )
                || ' ' ||
                v_last( MOD(TRUNC(v_inserted / v_first.COUNT), v_last.COUNT) + 1 );

    /* Genre restricted to your list */
    v_genre := v_genres( MOD(v_inserted, v_genres.COUNT) + 1 );

    /* Year in [1950, 2024] (upper bound exclusive in DBMS_RANDOM) */
    v_year := TRUNC(DBMS_RANDOM.VALUE(1950, 2025));

    /* Prices and popularity */
    v_sales    := ROUND(DBMS_RANDOM.VALUE(15, 150), 2);
    v_purchase := ROUND(v_sales * 0.8, 2);
    v_pop      := ROUND(DBMS_RANDOM.VALUE(1, 5), 1);
    IF v_pop < 1 THEN v_pop := 1; END IF;
    IF v_pop > 5 THEN v_pop := 5; END IF;

    INSERT INTO BookTitles (bookId, title, author, genre, publicationYear, purchasePrice, salesPrice, popularity)
    VALUES (v_id, v_title, v_author, v_genre, v_year, v_purchase, v_sales, v_pop);

    v_inserted := v_inserted + 1;

    IF MOD(v_inserted, 1000) = 0 THEN
      COMMIT;
      DBMS_OUTPUT.PUT_LINE('Inserted ' || v_inserted || ' rows...');
    END IF;
  END LOOP;

  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Done. Inserted total rows: ' || v_inserted);
END;
/


BEGIN
  populate_booktitles_9k; -- or populate_booktitles_6k(5500);
END;
/

select * from BOOKTITLES where bookId ='B0009';