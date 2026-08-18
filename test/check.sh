set -euo pipefail

GO_STAT="http://127.0.0.1:17011"
PHP_API="http://127.0.0.1:18080"
PASS=0
FAIL=0

check() {
  local desc="$1" actual="$2" expected="$3"
  if [ "$actual" = "$expected" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (got: $actual, want: $expected)"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Go-сервис: валидация ==="

STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  "$GO_STAT/stat?actionType=impression&placement=placement-video-main&price=5.00&requestId=test-ok")
check "valid event → 202" "$STATUS" "202"

STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  "$GO_STAT/stat?actionType=impression&placement=&price=1.00")
check "empty placement → 400" "$STATUS" "400"

STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  "$GO_STAT/stat?actionType=impression&placement=missing-placement&price=1.00")
check "unknown placement → 400" "$STATUS" "400"

STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  "$GO_STAT/stat?actionType=unknown_action&placement=placement-video-main&price=1.00")
check "unknown actionType → 400" "$STATUS" "400"

echo ""
echo "=== Go-сервис: расчёт цены ==="

curl -s -o /dev/null "$GO_STAT/stat?actionType=impression&placement=placement-video-main&price=12.34&requestId=test-price"
CENTS=$(docker compose exec -T postgres psql -U app -d stat_pipeline -t -c \
  "SELECT price_cents FROM raw_events WHERE request_id='test-price' LIMIT 1;" | tr -d ' ')
check "price=12.34 сохранено как 1234 cents" "$CENTS" "1234"

echo ""
echo "=== PHP API: фильтр placement_id ==="

ROWS=$(curl -s "$PHP_API/api/daily-stats?date=2026-08-07&placement_id=placement-banner-sidebar" \
  | grep -o '"placement_id"' | wc -l | tr -d ' ')
check "фильтр по placement_id возвращает 1 строку" "$ROWS" "1"

echo ""
echo "=== Агрегация: идемпотентность ==="

docker compose exec -T php php bin/console aggregate:daily 2026-08-07 > /dev/null
docker compose exec -T php php bin/console aggregate:daily 2026-08-07 > /dev/null
COUNT=$(docker compose exec -T postgres psql -U app -d stat_pipeline -t -c \
  "SELECT COUNT(*) FROM daily_stats WHERE stat_date='2026-08-07';" | tr -d ' ')
check "повторная агрегация не дублирует строки (ожидаем 2)" "$COUNT" "2"

echo ""
echo "=== Итог: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
