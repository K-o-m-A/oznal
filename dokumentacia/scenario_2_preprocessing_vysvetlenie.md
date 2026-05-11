# Scenár 2 — preprocessing pipeline (Recept A)

Tento dokument vysvetľuje **preprocessing pipeline** pre Scenár 2 — kód, ktorý zo surových dát pripraví `train_std` a `test_std` použité v tréningu modelov **LR, LDA, NB, SVM-RBF, KNN**. Random Forest má vlastný recept (Recept B — bez preprocessingu), preto ide do tréningu bez tejto pipeline.

Pôvodný kód:

```r
feat <- df_sub %>% select(-label)
binary_features <- feat %>%
  select(where(~ all(na.omit(.x) %in% c(0, 1)))) %>%
  names()
continuous_features <- setdiff(names(feat), binary_features)

apply_log <- function(d, cols) {
  d %>%
    mutate(across(all_of(cols), ~ log1p(pmax(.x, 0))))
}
train_log <- apply_log(train_raw, continuous_features)
test_log  <- apply_log(test_raw,  continuous_features)

pp <- train_log %>%
  select(all_of(continuous_features)) %>%
  preProcess(method = c("center", "scale"))

replace_continuous <- function(d) {
  scaled <- d %>%
    select(all_of(continuous_features)) %>%
    predict(pp, .)

  d %>%
    mutate(across(all_of(continuous_features), ~ scaled[[cur_column()]]))
}

train_std <- replace_continuous(train_log)
test_std  <- replace_continuous(test_log)
```

---

## Krok 1: Separácia features od label

```r
feat <- df_sub %>% select(-label)
```

`df_sub` je 30k stratifikovaný subsample s features aj `label` stĺpcom. `feat` je ten istý data frame **bez label** — čistá feature matrica. Robíme to preto, lebo všetky ďalšie operácie (klasifikácia features na binárne/spojité, preprocessing) sa aplikujú **iba na features**, nie na cieľovú premennú.

---

## Krok 2: Detekcia binárnych features

```r
binary_features <- feat %>%
  select(where(~ all(na.omit(.x) %in% c(0, 1)))) %>%
  names()
```

Tu sa **automaticky detekuje**, ktoré features sú binárne — bez tvrdo zakódovaného zoznamu. Postup zvnútra navonok:

1. **`where(~ ...)`** — `dplyr` selector, ktorý prejde každý stĺpec a vyhodnotí lambda funkciu. Vyberie iba tie stĺpce, kde lambda vráti `TRUE`.
2. **`na.omit(.x)`** — odstráni `NA` z hodnôt feature. Bez toho by `NA %in% c(0,1)` vrátilo `NA`, čo by `all(...)` interpretovalo ako `FALSE` a zahodilo aj reálne binárne stĺpce s nejakými chýbajúcimi hodnotami.
3. **`%in% c(0, 1)`** — pre každú hodnotu skontroluje, či je 0 alebo 1. Vráti logical vector.
4. **`all(...)`** — `TRUE` iba ak **všetky** hodnoty sú v `{0, 1}`. Stačí jedna hodnota mimo, a stĺpec sa nezaradí medzi binárne.
5. **`%>% names()`** — z výslednej tabuľky vyberie iba mená stĺpcov.

Výsledok: vector mien binárnych features — typicky `IsHTTPS`, `HasTitle`, `Bank`, `Pay`, `Crypto`, `IsDomainIP`, `HasSocialNet`, `HasCopyrightInfo`, `HasDescription`, `HasSubmitButton`, `HasHiddenFields`, atď. Spolu by to malo byť okolo 18 features (7 Trust + 11 binárnych Behavior).

**Prečo automatická detekcia a nie hardcoded zoznam:** keby sme niekedy zmenili pool prediktorov (pridali alebo vyhodili feature), kód by sa neaktualizoval ručne — automaticky správne klasifikuje, čo je binárne a čo nie.

---

## Krok 3: Spojité features ako doplnok

```r
continuous_features <- setdiff(names(feat), binary_features)
```

`setdiff(A, B)` vráti prvky `A`, ktoré nie sú v `B`. Takže spojité = **všetky features mínus binárne**. To je 22 features (počty znakov, dĺžky, počty objektov na stránke).

**Prečo `setdiff` a nie samostatná detekcia:** logické komplementy sú menej náchylné na bug. Ak by sme robili druhú detekciu typu „is.numeric a má aspoň 3 unique hodnoty", mohli by sme niečo prehliadnuť. Takto je garantované, že `binary_features ∪ continuous_features = všetky features`.

---

## Krok 4: Definícia transformácie `log1p + pmax`

```r
apply_log <- function(d, cols) {
  d %>%
    mutate(across(all_of(cols), ~ log1p(pmax(.x, 0))))
}
```

Funkcia, ktorá vezme data frame `d` a zoznam stĺpcov `cols`, a v týchto stĺpcoch aplikuje `log1p(pmax(x, 0))`. Rozoberme zložené volanie:

- **`pmax(.x, 0)`** — element-wise maximum z hodnoty a nuly. Záporné hodnoty oreže na 0. Toto je **defenzívna ochrana**: count features by mali byť `≥ 0` z definície (počet znakov nemôže byť záporný), ale ak by sa niekedy v dátach objavila negatívna hodnota (napr. artefakt parsovania), `log1p(záporné)` by spadlo. `pmax` to chytí.
- **`log1p(...)`** — `log(1 + x)`. Stláča dlhý pravý chvost (rieši šikmosť), bezpečné v nule (`log1p(0) = 0`). Aplikuje sa na výsledok `pmax`.
- **`across(all_of(cols), ~ ...)`** — `dplyr` API, ktoré aplikuje funkciu na každý stĺpec v `cols`. `all_of(cols)` zlyhá, ak by sa niektorý stĺpec nenašiel (na rozdiel od `any_of`, ktoré by ticho preskočilo).
- **`mutate(...)`** — vráti modifikovaný data frame, kde `cols` stĺpce majú nové hodnoty, a všetky ostatné stĺpce ostávajú nezmenené.

**Prečo závislé od `cols` argumentu:** funkcia je **generická** — môžeme ju zavolať s rôznymi zoznamami stĺpcov. V praxi ju voláme s `continuous_features`, takže binárky sa transformácie vôbec nedotkne.

---

## Krok 5: Aplikácia logaritmu na train aj test

```r
train_log <- apply_log(train_raw, continuous_features)
test_log  <- apply_log(test_raw,  continuous_features)
```

Aplikujeme `log1p + pmax` na **obe** sady — train aj test — s tým istým zoznamom stĺpcov. Po tomto riadku:

- `train_log` má spojité features na log škále, binárky aj label nezmenené.
- `test_log` to isté.

**Prečo musíme transformovať aj test:** ak by sme transformovali iba train a model trénovali na log dátach, ale predikovali na surových test dátach, model by dostal úplne inú škálu vstupov a predikcie by boli nezmysel.

**Prečo `log1p` nemá problém s leakage train→test:** logaritmus je **deterministická funkcia** — `log1p(50) = 3.93` bez ohľadu na zvyšok datasetu. Nepotrebuje fit (na rozdiel od štandardizácie, ktorú riešime za chvíľu).

---

## Krok 6: Fit štandardizácie na train

```r
pp <- train_log %>%
  select(all_of(continuous_features)) %>%
  preProcess(method = c("center", "scale"))
```

Tu už **fit-ujeme** (učíme) preprocessing parametre **iba na train**:

1. **`select(all_of(continuous_features))`** — z train vyfiltrujeme iba spojité features (na ne aplikujeme štandardizáciu). Binárky neštandardizujeme — `IsHTTPS = 1` po standardizácii by stratilo svoju 0/1 interpretáciu.
2. **`preProcess(method = c("center", "scale"))`** — `caret` funkcia, ktorá **odhadne priemer a smerodajnú odchýlku každého stĺpca** v train sete. Vráti objekt `pp`, ktorý si tieto parametre pamätá.

Po tomto kroku `pp` obsahuje **22 priemerov a 22 smerodajných odchýlok** (jeden pár pre každú spojitú feature) odhadnutých z train log dát.

**Prečo iba na train — kritické pravidlo:** keby sme štandardizáciu fittovali na celom datasete (train + test), test by „nakukol" do train procesu — leakage. Test sad musí byť pri tréningu úplne neviditeľná. `pp` sa fit-uje na train a **rovnako** sa potom aplikuje na test.

---

## Krok 7: Helper funkcia na aplikáciu štandardizácie

```r
replace_continuous <- function(d) {
  scaled <- d %>%
    select(all_of(continuous_features)) %>%
    predict(pp, .)

  d %>%
    mutate(across(all_of(continuous_features), ~ scaled[[cur_column()]]))
}
```

Funkcia, ktorá vezme data frame `d` (train alebo test po `apply_log`) a vráti ho so **štandardizovanými spojitými features**, pričom binárky a label ostávajú nezmenené.

**Prvá časť — výpočet štandardizovaných hodnôt:**

```r
scaled <- d %>%
  select(all_of(continuous_features)) %>%
  predict(pp, .)
```

- `select(all_of(continuous_features))` — vezme iba spojité stĺpce.
- `predict(pp, .)` — `caret` použije uložené priemery a SD z `pp` na transformáciu: pre každý stĺpec spočíta `(x − μ) / σ`, kde `μ` a `σ` pochádzajú z **train**. Vráti data frame so štandardizovanými spojitými features.
- Bodka `.` je placeholder pre data frame z pipe — `predict(pp, .)` znamená „použi `pp` na to, čo prišlo z pipe".

**Druhá časť — vrátenie štandardizovaných hodnôt späť do pôvodného frame:**

```r
d %>%
  mutate(across(all_of(continuous_features), ~ scaled[[cur_column()]]))
```

- `mutate(across(...))` opäť modifikuje stĺpce.
- `~ scaled[[cur_column()]]` — pre každý stĺpec v `continuous_features` zoberie z `scaled` rovnomenný stĺpec a nahradí ho. `cur_column()` je `dplyr` helper, ktorý vráti meno aktuálne spracovávaného stĺpca.

**Výsledok:** data frame s rovnakou štruktúrou ako vstup (rovnaké stĺpce, rovnaký `label`), ale spojité features sú teraz štandardizované.

**Prečo nie jednoducho `predict(pp, d)`:** `predict.preProcess` by transformoval len tie stĺpce, ktoré `pp` pozná (čiže spojité), ale **vrátil by data frame iba so spojitými stĺpcami** — stratili by sme binárky a label. Náš helper to robí konzervatívne — pôvodný frame sa zachová kompletný, len spojité stĺpce sa nahradia.

---

## Krok 8: Aplikácia na train aj test

```r
train_std <- replace_continuous(train_log)
test_std  <- replace_continuous(test_log)
```

- `train_std` — train po `log1p + center/scale` na spojitých features. Toto je vstup do `caret::train` pre LR, LDA, NB, SVM, KNN.
- `test_std` — test po **rovnakej** transformácii. Použije sa pre `predict(fit, test_std)` v hold-out vyhodnotení.

Kľúčová vlastnosť: **rovnaké priemery a SD** (z `pp`, fit-nuté na train) sa aplikujú na test. Test ich nezmenil — len ich „dostal" cez `predict(pp, ...)`.

---

## Prečo táto pipeline ako celok

### 1. Iba na spojité features

Binárne features (`IsHTTPS`, `Bank`, `HasSocialNet`, ...) **nepreprocessujeme**:

- `log1p(0) = 0`, `log1p(1) = 0.69` — z 0/1 by sa stalo 0/0.69. Bezvýznamné.
- Štandardizácia na 0/1 dáta by ich premenila na ~ `±1.5`, ale stratil by sa intuitívny binárny význam. Modely by si poradili, ale nič sa tým nezíska.

### 2. Poradie `log1p` → `center/scale`

`log1p` rieši **tvar** rozdelenia (chvosty, šikmosť). `center/scale` rieši **lokáciu a škálu** (priemer 0, SD 1). Ak by sme to robili naopak (najprv standardizácia, potom log), `log1p` by sa aplikovalo na hodnoty s priemerom 0, čo môže produkovať záporné hodnoty, a `pmax` by ich orezal — stratili by sme variabilitu.

### 3. `pp` fit-ované iba na train

Zlatá zásada ML metodiky — preprocessing parametre, ktoré sa odhadujú z dát (priemer, SD), sa **musia fit-ovať iba na train**. Inak je to leakage a test už nie je nezávislé hold-out.

### 4. Random Forest dostane iné dáta

V skripte ďalej je samostatný recept B pre RF: **bez `log1p`, bez `center/scale`** — RF rozhoduje cez prahy, monotónne transformácie nemenia výsledok. Preto má tento preprocessing pipeline žiadny dosah na RF, ktorý dostane surové `train_raw`/`test_raw`.

---

## Zhrnutie krokov

| Krok | Funkcia | Vstup | Výstup |
|------|---------|-------|--------|
| 1 | `feat <- df_sub %>% select(-label)` | full subsample | features only |
| 2 | `binary_features <-` ... | feat | mená 0/1 stĺpcov |
| 3 | `continuous_features <- setdiff(...)` | feat, binary | mená spojitých |
| 4 | `apply_log()` | df, stĺpce | df s log spojitých |
| 5 | aplikácia na train + test | train_raw, test_raw | train_log, test_log |
| 6 | `pp <- preProcess(...)` | train_log spojité | fit objekt s μ, σ |
| 7 | `replace_continuous()` | df, pp | df so štandard. spojitými |
| 8 | aplikácia na train + test | train_log, test_log | **train_std, test_std** |

`train_std` a `test_std` sú finálne vstupy pre 5 modelov (LR, LDA, NB, SVM, KNN). RF dostáva `train_raw`, `test_raw` priamo.
