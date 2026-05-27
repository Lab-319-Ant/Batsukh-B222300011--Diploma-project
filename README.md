# AI/ML-д суурилсан LTE SON симуляцийн төсөл

Энэ repository нь MATLAB дээр боловсруулсан LTE сүлжээний симуляцийн төсөл юм. Төслийн зорилго нь 7 сайт, 21 сектор бүхий LTE радио хандалтын сүлжээнд KPI үүсгэх, machine learning ашиглан сүлжээний төлөвийг илрүүлэх, action recommendation гаргах, safety check хийх, oracle benchmark-тэй харьцуулах явдал юм.

Энэ project нь **2 тусдаа хэсэгтэй**.

---

## 1. Synthetic LTE simulation

Энэ нь хийсвэр LTE RAN симуляци юм.

Үүнд:

- 7 сайт
- 21 сектор
- 500 UE
- RSRP map
- SINR map
- UE attachment
- sector load
- traffic KPI
- COD
- COC/OH
- TP
- QP
- safety check
- coordinator decision
- oracle comparison

зэрэг үр дүн гарна.

### Ажиллуулах файл

MATLAB дээр дараах folder-ийг нээнэ.

```text
ai_lte_son_single_site
```

Дараа нь MATLAB Command Window дээр:

```matlab
main
```

гэж бичээд Enter дарна.

### Үр дүн гарах folder

```text
ai_lte_son_single_site/results/figures/
ai_lte_son_single_site/results/tables/
```

### Үзэх гол зургууд

```text
results/figures/phase1b_topology_ue_attachment.png
results/figures/phase1b_best_rsrp_map.png
results/figures/phase1b_best_sinr_map.png
results/figures/phase2_sector_load_map.png
results/figures/phase6b_cod_test_confusion_matrix.png
results/figures/phase7b_tp_actual_vs_predicted.png
results/figures/phase12e_baseline_ai_oracle_kpis.png
```

Эдгээр зураг нь topology, coverage, SINR, load, ML result болон final comparison-ийг харуулна.

---

## 2. Real KPI replay / advisory simulation

Энэ хэсэг нь өмнөх real KPI Excel файлуудыг уншиж offline шинжилгээ хийдэг.

Энэ нь бодит сүлжээнд parameter өөрчилдөггүй. Зөвхөн KPI data дээр үндэслэж advisory result гаргана.

Үүнд:

- real KPI file унших
- KPI цэвэрлэх
- 7 site / 21 селл mapping хийх
- COD state timeline гаргах
- COC recommendation гаргах
- TP overload warning гаргах
- QP degradation warning гаргах
- ES sleep gate check хийх

ажлууд орно.

### Real KPI input folder

`KPI` folder нь `ai_lte_son_single_site` folder-ийн гадна талд байх ёстой.

Зөв бүтэц:

```text
batsukh/
├── KPI/
└── ai_lte_son_single_site/
```

### Ажиллуулах файл

MATLAB дээр:

```text
ai_lte_son_single_site
```

folder-ийг Current Folder болгоно.

Дараа нь Command Window дээр:

```matlab
run_vendor_kpi_recommendation
```

гэж бичээд Enter дарна.

### Үр дүн гарах folder

```text
ai_lte_son_single_site/results/vendor/figures/
ai_lte_son_single_site/results/vendor/tables/
```

### Үзэх гол зургууд

```text
results/vendor/figures/vendor_cod_state_timeline.png
results/vendor/figures/vendor_coc_ml_teacher_summary.png
results/vendor/figures/vendor_tp_overload_summary.png
results/vendor/figures/vendor_qp_degradation_summary.png
results/vendor/figures/vendor_es_sleep_summary.png
```

---

## Project-ийг GitHub-оос татаж ажиллуулах

1. QR code уншуулна.
2. GitHub repository нээгдэнэ.
3. Repository private бол GitHub account-аараа login хийнэ.
4. `Code` товч дарна.
5. `Download ZIP` дарна.
6. ZIP файлыг extract хийнэ.
7. MATLAB нээнэ.
8. `ai_lte_son_single_site` folder-ийг Current Folder болгоно.
9. Synthetic simulation ажиллуулах бол:

```matlab
main
```

10. Real KPI replay ажиллуулах бол:

```matlab
run_vendor_kpi_recommendation
```

---

## Багшид тайлбарлах товч утга

Энэ project нь хоёр төрлийн үнэлгээтэй.

Нэгдүгээрт, MATLAB дээр 7 сайт, 21 сектор, 500 UE бүхий synthetic LTE simulation хийж RSRP, SINR, throughput, load, COD, TP, QP, COC/OH, safety check, coordinator decision болон oracle comparison гаргасан.

Хоёрдугаарт, real KPI Excel файлуудыг ашиглан offline KPI replay/advisory analysis хийсэн. Энэ хэсэг нь real KPI data-г уншиж COD state timeline, COC recommendation, TP overload warning, QP degradation warning, ES sleep gate check гаргадаг.

Synthetic simulation нь simulator-ийн behavior-ийг харуулна. Real KPI branch нь бодит KPI file дээр шинжилгээ хийж чаддагийг харуулна. Гэхдээ real KPI branch нь бодит сүлжээнд parameter өөрчилсөн live optimization биш.

---

## Анхаарах зүйл

Энэ project-ийг дараах байдлаар тайлбарлах нь зөв.

```text
MATLAB-based AI/ML-assisted LTE SON-inspired simulation and offline KPI advisory framework
```

Дараах байдлаар тайлбарлаж болохгүй.

```text
Full real AI-RAN deployment
Live closed-loop SON system
Real network healing баталсан систем
```

---

## Private GitHub ба QR code

QR code нь зөвхөн GitHub link рүү оруулна. Repository private бол зөвхөн invite авсан GitHub account-аар орж чадна.

Зөв дараалал:

```text
QR уншуулна
↓
GitHub repository нээгдэнэ
↓
GitHub login хийнэ
↓
Invite авсан багш project-ийг үзнэ
```

Invite аваагүй хүн QR уншуулбал 404 гарч болно. Энэ нь private repository дээр хэвийн.

---

## Гол folder-ууд

```text
KPI/                                      real KPI Excel files
ai_lte_son_single_site/main.m             synthetic simulation
ai_lte_son_single_site/run_vendor_kpi_recommendation.m   real KPI replay
ai_lte_son_single_site/results/figures/   synthetic figures
ai_lte_son_single_site/results/tables/    synthetic tables
ai_lte_son_single_site/results/vendor/    real KPI replay results
```

---

## Товч дүгнэлт

Энэ repository нь LTE сүлжээнд AI/ML ашиглан KPI шинжилгээ, төлөв илрүүлэлт, action recommendation болон oracle comparison хийх MATLAB project юм. Project нь synthetic simulation болон real KPI replay гэсэн хоёр тусдаа хэсэгтэй. Багш нар GitHub дээрээс project-ийг татаж авч MATLAB дээр `main` болон `run_vendor_kpi_recommendation` файлуудыг ажиллуулж үр дүнг шалгаж болно.
