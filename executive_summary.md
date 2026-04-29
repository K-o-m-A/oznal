# Executive Summary - Phishing URL Detection

## Domain background

When a user clicks a link, the corporate proxy has milliseconds to decide if it's safe. The cheapest check available is the URL string itself - no page load, no DNS lookup, nothing fancy. The core question this project answers is: **how much phishing signal already lives in a URL, and what's the simplest model that can act on it reliably?**

We use the PhiUSIIL dataset and group features into three tiers by cost: **Lexical** (URL string only), **Trust** (light domain checks), and **Behavior** (full page fetch).

## Scenario 2 - Which model family extracts more signal from a URL-only feature set?

Is a non-parametric model (Random Forest, SVM-RBF, KNN) better than a parametric one (Logistic Regression, LDA, Naive Bayes) when the only available signal is the raw URL string? And does that gap shrink as we feed the model richer page-level features?

**Why these models.**

- **LR-Ridge** handles the heavy correlation between URL length, letter count, and digit count that breaks plain logistic regression.
- **LDA** is a second linear baseline.
- **Naive Bayes** is the intentional control. It ignores feature overlap entirely, and we wanted to quantify how much that hurts.
- **Random Forest** finds feature combinations (long URL + many digits, for example) that no single feature captures alone.
- **SVM-RBF** does the same with smooth boundaries instead of decision rules.
- **KNN** makes no assumptions at all, which is useful given the skew and correlation found during EDA.

**Key findings.**

- **On URL-only features, non-parametric models win decisively.** SVM-RBF reaches roughly 99% AUC and keeps both false-positive and false-negative rates near 2%. The best parametric model (LDA) ranks well by AUC but blocks roughly 31% of legitimate URLs at the default decision threshold, unusable in production.
- **The gap closes as the feature set gets richer.** On the FullLite tier (Lexical + Trust + most Behavior signals) every model increases its accuracy and the family contrast disappears.
- **AUC alone is misleading.** Most models post high AUC scores on URL-only features but collapse at the threshold the proxy should use (0.5). We therefore evaluated every model on the operational metric `min(Sensitivity, Specificity)`, i.e. the worst of *"phishing caught"* and *"legitimate links let through"*.

**Recommendation.** For the URL-only first-line filter we recommend **SVM-RBF**. It's the only model where precision, sensitivity, and specificity all sit near 0.98 simultaneously with no threshold tuning. KNN reaches similar quality but slows down as the training set grows.

## Scenario 4 - Making the model explainable

In case the managers prefer Random Forest over our recommendation, we trained a **surrogate decision tree** that mimics the Random Forest's predictions rather than the original labels. It reproduces ~96% of the RF's decisions with a tree small enough to present on a single slide, and its top split matches the RF's most important feature, confirming it's a faithful representation rather than a simplification.

## Scenario 3 - Feature selection on the URL-only filter

*[To be added once Scenario 3 is finalised.]*

## Summary

URL strings already carry enough signal to catch most phishing without ever loading the page, but extracting that signal cleanly requires a non-linear model. **SVM-RBF is the recommended deployment.** If Random Forest is preferred instead, the surrogate tree gives the security team a readable explanation for every blocked URL. Linear models remain useful once richer features are available.
