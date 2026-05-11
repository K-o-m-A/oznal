Daj mi jednu vetu prečo sme zvolili # EDA — Near-leaker analýza: kód, motivácia a výsledky

Tento dokument vysvetľuje, ako sme v EDA identifikovali **near-leaker features** — Behavior features, ktoré samostatne (bez akéhokoľvek modelu) klasifikujú phishing takmer perfektne. Toto zistenie priamo motivovalo zavedenie **FullLite tieru** v Scenári 2. Pôvodný kód je v `eda.rmd`, chunk `near-leaker-auc`.

---

## 1. Čo je near-leaker a prečo nás zaujímal

**Near-leaker** je feature, ktorá je tak silne korelovaná s targetom, že **sama o sebe vyrieši klasifikáciu takmer dokonale**. Nie je to leak v striktnom zmysle (nie je to `label` zakódovaný v inej premennej), ale pre účely porovnania modelov sa správa rovnako škodlivo:

- Akýkoľvek model — aj najjednoduchší (jeden split rozhodovacieho stromu, jeden lineárny term v LR) — dosiahne **AUC blízko 1.0** len vďaka nej.
- **Rozdiel medzi modelmi sa stratí** — všetky modely vyzerajú rovnako dobre, lebo úloha je triviálna.
- **H1 hypotéza nedáva zmysel** — nemôžeme tvrdiť, že neparametrické modely majú výhodu, ak parametrické tiež saturujú pri AUC 0.99 vďaka jedinému silnému stĺpcu.

Preto sme potrebovali objektívnu mieru, **ktoré features sú samostatne tak silné**, že úlohu robia trivial. Univariate AUC je presne tá miera.

---

## 2. Univariate AUC — čo to je

**Univariate AUC** = AUC získaná tak, že **samotnú hodnotu jednej feature použijeme ako skóre**. Žiadny model, žiadne fit-tovanie — feature priamo slúži ako predikčné skóre.

Interpretácia:

- **AUC = 0.5** — feature nemá žiadnu rozlišovaciu silu samostatne.
- **AUC = 0.8** — feature samostatne rozumne rozlišuje (slabý-stredný klasifikátor).
- **AUC = 0.95** — feature **samostatne klasifikuje takmer perfektne**. Stačí prahový split a model je hotový.
- **AUC = 1.0** — feature deterministicky určuje triedu.

Náš prah `0.95` pre near-leaker je konvenčný — features nad ním sú „príliš dobré", aby sa s nimi dalo férovo porovnávať modely.

---

## 3. Kód — riadok po riadku

```r
behavior_feats <- family_map %>% filter(family == "Behavior") %>% pull(feature)
label_factor   <- factor(df$label, levels = c(0, 1))

univariate_aucs <- tibble(
  feature = behavior_feats,
  auc = map_dbl(behavior_feats, ~
    roc_auc_vec(
      truth       = label_factor,
      estimate    = features[[.x]],
      event_level = "second"
    )
  )
) %>%
  arrange(desc(auc))

LEAKY_BEHAVIOR <- univariate_aucs %>%
  filter(auc > 0.95) %>%
  pull(feature)
```

### 3.1 Výber Behavior features

```r
behavior_feats <- family_map %>% filter(family == "Behavior") %>% pull(feature)
```

`family_map` je tibble, ktorý každej feature priraďuje rodinu (Lexical / Trust / Behavior). Tu vyfiltrujeme iba Behavior features a `pull(feature)` vyberie stĺpec ako vector mien.

**Prečo iba Behavior:** Z pohľadu deployment scenára sú práve Behavior features tie najdrahšie (vyžadujú stiahnutie a parsovanie stránky), takže je dôležité vedieť, **ktoré z nich sú zbytočne silné** — keby sme ich nechali v experimente, overshadovali by všetky ostatné. Lexical a Trust majú samostatne slabšie features (zo zistení SMD a Cramér's V), takže problém near-leakerov je doménou Behavior rodiny.

### 3.2 Príprava label ako factor

```r
label_factor <- factor(df$label, levels = c(0, 1))
```

`yardstick::roc_auc_vec` vyžaduje **factor** ako truth, nie numerickú hodnotu. Explicitné nastavenie `levels = c(0, 1)` zaručuje:

- Prvá úroveň je `0` (Legitimate),
- Druhá úroveň je `1` (Phishing).

To je kritické pre nasledujúci `event_level = "second"` argument.

### 3.3 Výpočet univariate AUC pre každú feature

```r
univariate_aucs <- tibble(
  feature = behavior_feats,
  auc = map_dbl(behavior_feats, ~
    roc_auc_vec(
      truth       = label_factor,
      estimate    = features[[.x]],
      event_level = "second"
    )
  )
) %>%
  arrange(desc(auc))
```

Zložené volanie:

1. **`tibble(feature = behavior_feats, auc = ...)`** — vytvoríme dvojstĺpcový tibble. Prvý stĺpec je meno feature, druhý je jej univariate AUC.
2. **`map_dbl(behavior_feats, ~ ...)`** — `purrr` map, ktorá pre každé meno feature spočíta jedno číslo (preto `_dbl` — vracia double vector). `~` je shorthand pre lambda funkciu, kde `.x` je aktuálne meno feature.
3. **`roc_auc_vec(...)`** — `yardstick` funkcia, ktorá zo skutočných labelov a skóre vráti AUC ako skalár.
4. **`features[[.x]]`** — vyberie stĺpec `features` podľa mena feature. `[[ ]]` namiesto `[ ]` lebo chceme vector, nie data frame.
5. **`event_level = "second"`** — povie, ktorá úroveň factoru je positive class. `levels = c(0, 1)` znamená, že **druhá úroveň je 1 (Phishing)** — to je správne, lebo phishing je positive event.
6. **`arrange(desc(auc))`** — zoradenie od najsilnejšej feature po najslabšiu.

**Kritická detail:** keby `event_level = "first"`, AUC by sa preklopila na `1 − AUC`. Takto sa dá metrika ľahko pomýliť, preto si v tomto kóde pozorne kontrolujeme orientáciu factoru (`levels = c(0, 1)`) **a** event_level argument.

### 3.4 Identifikácia near-leakerov

```r
LEAKY_BEHAVIOR <- univariate_aucs %>%
  filter(auc > 0.95) %>%
  pull(feature)
```

Z usporiadanej tabuľky vyfiltrujeme všetky features s AUC nad prahom **0.95** a uložíme ich mená do globálnej premennej `LEAKY_BEHAVIOR`. Tá sa neskôr v Scenári 2 použije na **odstránenie near-leakerov** zo Behavior tieru a vytvorenie FullLite tieru:

```r
behavior_clean <- setdiff(behavior_feats, LEAKY_BEHAVIOR)  # 20 - 6 = 14
fulllite      <- c(lexical_feats, trust_feats, behavior_clean)  # 34 features
```

**Prečo prah 0.95 a nie napríklad 0.90:**

- `0.95` je dostatočne ostrý prah, aby zachytil iba **extrémne silné** features. Pri 0.90 by sme potenciálne odstránili aj features, ktoré sú síce silné, ale nie „triviálne".
- Empiricky sa v našom datasete nenašli features s AUC medzi 0.90 a 0.95 — gap medzi „normálnymi" Behavior (najsilnejšia ~0.85) a „near-leakers" (najslabší ~0.96) je výrazný. Takže prah 0.95 je v tomto zmysle „naturally chosen" — leží v prirodzenej medzere medzi dvoma populáciami features.
- V literatúre sa `0.95` používa štandardne pre „prakticky perfektný klasifikátor" v binárnych úlohách.

---

## 4. Čo sme zistili

### 4.1 Šesť near-leakerov

Z 20 Behavior features sa **6 ukázalo ako near-leakers**:

| Feature | Univariate AUC | Prečo je takmer perfektný |
|---|---|---|
| `LineOfCode` | > 0.99 | Legit stránky sú zložitejšie, viac kódu |
| `NoOfExternalRef` | 0.990 | Phishing nereferencuje externé zdroje |
| `NoOfImage` | 0.985 | Phishing stránky majú minimum obrázkov |
| `NoOfSelfRef` | 0.980 | Legit stránky majú veľa interných odkazov |
| `NoOfJS` | 0.970 | Phishing sa vyhýba JavaScriptu |
| `NoOfCSS` | 0.958 | Phishing minimalizuje stylesheets |

### 4.2 Geometrická interpretácia

Phishing stránka je typicky **plytká HTML shell** — formulár s pár vstupmi, jednoduchý layout, žiadne externé zdroje, žiadny komplexný JavaScript. Cieľom phishingu je **rýchlo zachytiť credentials**, nie vytvoriť presvedčivú web aplikáciu. Naopak legit stránky banky alebo platformy sú **bohaté HTML aplikácie** so stovkami riadkov kódu, desiatkami obrázkov, externými trackingovými skriptami atď.

Tento kontrast je tak ostrý, že už **jeden prah na `LineOfCode` < 50** klasifikuje phishing s takmer perfektnou presnosťou. Inými slovami: dataset má **datasetovú špecifickú vlastnosť**, ktorá robí úlohu trivialnou, ak sa použijú celé Behavior features.

---

## 5. Saturation problem — prečo to bol pre H1 problém

Ak by sme **nechali všetkých 20 Behavior features** v plnom Behavior tieri (a teda aj v plnom Full = Lexical + Trust + Behavior), nastala by saturation:

- **Všetky modely** (LR, LDA, NB, RF, SVM, KNN) by dosiahli AUC ≈ 0.99+.
- **Rozdiel medzi parametrickými a neparametrickými** modelmi by zmizol — nie preto, že sú rovnako dobré, ale preto, že úloha je triviálna a každý zachytí to isté.
- **H1 by sme nemohli zmysluplne testovať** — gap medzi rodinami by bol blízky nule, ale nie z dôvodov, ktoré H1 predpovedá.

Inak povedané: keby sme zahrnuli near-leakerov, dostali by sme falošne **podporu C2 (gradient cez tiery)** — gap by sa zmenšil, ale **nie kvôli silným Trust/Behavior signálom** ako H1 tvrdí, ale kvôli jednému dominantnému stĺpcu, ktorý by všetkých klamal. To by celý experiment urobilo metodicky pochybným.

---

## 6. K čomu to nás viedlo — vznik FullLite tieru

Identifikácia 6 near-leakerov priamo motivovala dizajn **FullLite tieru** pre Scenár 2:

```
Behavior_clean = Behavior \ {6 near-leakers} = 14 features
FullLite = Lexical (13) + Trust (7) + Behavior_clean (14) = 34 features
```

FullLite je **neostro-saturujúci** tier:

- Stále má silné signály (Trust binárky `IsHTTPS`, `HasSocialNet`, zvyšok Behavior).
- Ale úloha **nie je triviálna** — žiadna jediná feature ju nerozhodne.
- **H1 gradient sa dá čítať**: ak parametrické a neparametrické modely majú podobný výkon na FullLite, ale neparametrické výrazne vyhrávajú na Lexical, **gap sa znížil legitímne** (vďaka silným Trust/Behavior signálom), nie umelo (vďaka leakerom).

Dôvodom, prečo robíme aj **Behavior tier samotný (bez near-leakerov)**, je rovnaký — chceme vidieť, aký je rozdiel medzi rodinami modelov, keď model dostane čisté Behavior features bez triviálnej úlohy.

---

## 7. Limity tejto analýzy

- **Dataset-specific.** Near-leakery, ktoré sme identifikovali, sú vlastnosťou **PhiUSIIL datasetu**, nie obecnou pravdou o phishingu. V inom datasete (napr. iný zber phishing URLs cez iný mechanizmus) by mohli byť iné features dominantné. Pre produkčné nasadenie by sa táto analýza musela opakovať na cieľovom dataset.
- **Univariate je nadhodnotené.** Niektoré features s AUC `~0.85–0.90` môžu byť **v kombinácii** ešte silnejšie než near-leakery samostatne. Tým, že sa rozhodujeme iba podľa univariate AUC, môžeme prehliadnuť „kombinačné" leakery. Pre nás je to akceptabilné — chceme odstrániť **triviálne dominantné** features, nie všetky korelované.
- **Prah 0.95 je arbitrárny.** Ako bolo vysvetlené vyššie, leží v prirodzenej medzere v našich dátach, ale v inom kontexte by mohol byť 0.90 alebo 0.97. V `scenario_2_priprava_na_obhajobu.md` túto voľbu otvorene priznávame.

---

## 8. Zhrnutie

| Krok | Čo sme spravili | Výsledok |
|------|-----------------|----------|
| Kód | Univariate AUC pre každú Behavior feature cez `yardstick::roc_auc_vec` | 20 čísel AUC |
| Filter | Prah AUC > 0.95 | **6 near-leakerov** (`LineOfCode`, `NoOfExternalRef`, `NoOfImage`, `NoOfSelfRef`, `NoOfJS`, `NoOfCSS`) |
| Motivácia | Saturation problem v plnom Full tieri | Modely by všetky dosiahli AUC ~0.99 |
| Riešenie | **FullLite tier** = Lexical + Trust + Behavior \ near-leakers (34 features) | Neostro-saturujúci tier, na ktorom sa dá čítať H1 gradient |
| Dôsledok | Behavior tier sa testuje na 14 features, nie 20 | Čistý experiment |

### Krátka veta pre obhajobu

> „Univariate AUC sme spočítali pre každú Behavior feature cez `yardstick::roc_auc_vec`. Šesť features prekročilo prah `AUC > 0.95` — `LineOfCode`, `NoOfExternalRef`, `NoOfImage`, `NoOfSelfRef`, `NoOfJS`, `NoOfCSS`. Tieto **near-leakery** by samostatne rozhodli klasifikáciu pri AUC 0.99+, čo by sterilne zarovnalo všetky modely a zničilo H1 porovnanie. Preto sme ich zo Scenára 2 odstránili a vytvorili **FullLite tier** (34 features = Lexical + Trust + Behavior bez near-leakerov), na ktorom sa dá H1 gradient férovo merať."
