# SOLUTION.md

## Что было сломано и как исправлено

### 1. Фильтр `placement_id` в API
**Файл:** `php-app/src/Repository/StatsRepository.php`

Код проверял `$query['placement']`, но frontend и API отправляют параметр `placement_id`.
Исправлено: ключ изменён на `placement_id` в условии и при извлечении значения.

### 2. Идемпотентность агрегации
**Файл:** `php-app/src/Aggregation/DailyStatsAggregator.php`

Повторный запуск `aggregate:daily` за тот же день дублировал строки в `daily_stats`.
Исправлено: перед каждым INSERT добавлен DELETE по `(stat_date, placement_id)`.
Повторный запуск перезаписывает данные, не накапливает дубли.

### 3. Timezone в агрегации
**Файл:** `php-app/src/Aggregation/DailyStatsAggregator.php`

Диапазон дат считался в UTC, хотя бизнес-день определяется в `APP_TIMEZONE` (Europe/Moscow, UTC+3).
Исправлено: timezone берётся из `getenv('APP_TIMEZONE')` с фолбэком на UTC.

### 4. Валидация Go-сервиса
**Файл:** `go-stat/main.go`

Четыре проблемы:
- `price=12.34` сохранялось как `12` cents вместо `1234` — исправлено через `math.Round(price * 100)`
- Неизвестный `placement` принимался без проверки — добавлен запрос `EXISTS` к таблице `placements`
- Неизвестный `actionType` принимался без проверки — добавлена проверка через `switch`
- Пустые параметры не отклонялись — добавлена проверка на пустую строку с возвратом HTTP 400

## Как проверялось

```bash
bash test/check.sh
```

7 интеграционных проверок через реальные HTTP-запросы и SQL-запросы к БД:
валидация Go-сервиса, корректность хранения цены, фильтр API, идемпотентность агрегации.

## Поток данных

```
seed:demo-events (PHP CLI)
  → отправляет события на Go /stat
  → Go валидирует: существует ли placement и известен ли actionType?
  → принятые события → INSERT в raw_events (price в cents)

aggregate:daily YYYY-MM-DD (PHP CLI)
  → SELECT из raw_events за бизнес-день в APP_TIMEZONE
  → DELETE + INSERT в daily_stats по каждому placement

GET /api/daily-stats?date=...&placement_id=... (PHP API)
  → SELECT из daily_stats с фильтром по дате и placement
  → JSON → dashboard
```
