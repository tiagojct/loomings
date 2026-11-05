---
title: Digital health and lung function: citation test
bibliography: refs.bib
csl: chicago-author-date
---

# Digital health and lung function

This file tests citations. Change the `csl:` line in the frontmatter to one of
`vancouver`, `apa`, `ieee`, `chicago-author-date` or `american-medical-association`,
or to a local file such as `csl: vancouver.csl`. The reference list is rebuilt.

## Spirometry

Spirometry is standardised by joint guidelines [@miller2005; @graham2019].
Reference equations changed in 2012 [@quanjer2012], and the use of race in
them is now questioned [@bhakta2022]. The physiology behind the manoeuvre is in
the standard textbook [@west2012, pp. 95-110].

@quanjer2012 give equations for ages 3 to 95. Compare this with
[-@miller2005] where only the year appears, and with a range of sources
[@miller2005; @quanjer2012; @graham2019; @bhakta2022].

## Decision support

Early work on rule-based reasoning [@shortliffe1975] led to modern clinical
decision support [@sutton2020]. The field is covered in a full textbook
[@shortliffe2014, ch. 22] and in a history of the discipline [@haux2010].

## Machine learning

Reviews [@topol2019; @rajkomar2019] and a standard text [@hastie2009] cover the
methods. The transformer architecture [@vaswani2017] drives current language
models. Analyses used R [@rcore2024].

## Reporting and data

Report systematic reviews with PRISMA [@page2021], observational studies with
STROBE [@vonelm2007] and prediction models with TRIPOD [@collins2015]. Data
should follow the FAIR principles [@wilkinson2016].

Policy context is in the WHO strategy [@who2021]. A thesis on mobile health is
a further source type [@doe2019].

## Edge cases

A key that does not exist [@missing2000] should show a warning. A citation with
a prefix and suffix [see @west2012, p. 45; also @hastie2009, ch. 3, for context]
tests the locator.

## References
