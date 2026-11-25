-- مخبزك: قاعدة بيانات SQLite تعمل بدون إنترنت (حسب المواصفة الفنية والمحاسبية النهائية)
-- المبالغ أعداد صحيحة (جنيه). الكميات بالكيلو. التواريخ بصيغة YYYY-MM-DD.
-- كل جدول متزامن فيه: id (UUID) و created_at و updated_at و device_id و synced،
-- حتى تُضاف المزامنة السحابية لاحقاً بدون تغيير الجداول.
-- لا حذف فعلي لأي صف: الإلغاء يكون بتعيين cancelled_at (والحذف ممنوع بـ triggers).
-- عزل المخابز: كل جدول يحمل bakery_id أو يستنتجه عبر day_id.
-- للمنفِّذ: فعّل PRAGMA foreign_keys = ON عند فتح كل اتصال، ولا تضع تعليقات داخل الجملة نفسها.

PRAGMA foreign_keys = ON;

-- ───────── المخابز والوكلاء (الكاتب: المالك فقط) ─────────
-- في النسخة الأولى (وكيل بدون سحابة) يُنشأ مخبز واحد ووكيل واحد عند التفعيل.

CREATE TABLE bakeries (
  id TEXT PRIMARY KEY,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  device_id TEXT,
  synced INTEGER NOT NULL DEFAULT 0,
  name TEXT NOT NULL,
  address TEXT,
  active INTEGER NOT NULL DEFAULT 1,
  cancelled_at TEXT
);

CREATE TABLE agents (
  id TEXT PRIMARY KEY,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  device_id TEXT,
  synced INTEGER NOT NULL DEFAULT 0,
  name TEXT NOT NULL,
  phone TEXT,
  active INTEGER NOT NULL DEFAULT 1,
  cancelled_at TEXT
);

-- الربط والتاريخ: started_at و ended_at تاريخان شاملان (ended_at فارغ = نشط)
CREATE TABLE agent_bakery (
  id TEXT PRIMARY KEY,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  device_id TEXT,
  synced INTEGER NOT NULL DEFAULT 0,
  agent_id TEXT NOT NULL REFERENCES agents(id),
  bakery_id TEXT NOT NULL REFERENCES bakeries(id),
  started_at TEXT NOT NULL,
  ended_at TEXT,
  CHECK (ended_at IS NULL OR ended_at >= started_at)
);

-- لا وكيلان نشطان على نفس المخبز، ولا وكيل نشط على أكثر من مخبز
CREATE UNIQUE INDEX ux_agent_bakery_one_active_agent ON agent_bakery(bakery_id) WHERE ended_at IS NULL;

CREATE UNIQUE INDEX ux_agent_bakery_one_active_bakery ON agent_bakery(agent_id) WHERE ended_at IS NULL;

-- ───────── الجهاز والإعدادات والمزامنة المحلية ─────────

-- صف واحد فقط: دور هذا الجهاز يحدده رمز التفعيل
CREATE TABLE device (
  id TEXT PRIMARY KEY,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  device_id TEXT,
  synced INTEGER NOT NULL DEFAULT 0,
  role TEXT NOT NULL CHECK (role IN ('owner', 'agent')),
  bakery_id TEXT REFERENCES bakeries(id),
  agent_id TEXT REFERENCES agents(id),
  activated_at TEXT NOT NULL,
  activation_code_hash TEXT NOT NULL,
  CHECK (role <> 'agent' OR (bakery_id IS NOT NULL AND agent_id IS NOT NULL))
);

-- المفاتيح: window_price, distribution_price, target_per_sack, batch_size_kg, sack_size_kg
-- كلمة المرور ورمز PIN لا تُخزَّن هنا، بل في التخزين الآمن للجهاز (Keystore)
CREATE TABLE settings (
  bakery_id TEXT NOT NULL REFERENCES bakeries(id),
  key TEXT NOT NULL,
  value TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  device_id TEXT,
  synced INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (bakery_id, key)
);

-- صف واحد فقط
CREATE TABLE sync_state (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  device_role TEXT CHECK (device_role IN ('owner', 'agent')),
  last_pull_cursor INTEGER NOT NULL DEFAULT 0,
  last_push_at TEXT,
  last_pull_at TEXT
);

INSERT INTO sync_state (id) VALUES (1);

-- احتياطي لتسجيل أي تعارض نادر
CREATE TABLE sync_conflicts (
  id TEXT PRIMARY KEY,
  table_name TEXT NOT NULL,
  row_id TEXT NOT NULL,
  detail TEXT,
  resolved INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

-- ───────── اليوم وإنتاجه ─────────

-- الأسعار والمستهدف تُنسخ إلى اليوم عند إنشائه، فلا يتغير حساب يوم قديم إذا تغيّر السعر
CREATE TABLE days (
  id TEXT PRIMARY KEY,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  device_id TEXT,
  synced INTEGER NOT NULL DEFAULT 0,
  bakery_id TEXT NOT NULL REFERENCES bakeries(id),
  agent_id TEXT NOT NULL REFERENCES agents(id),
  date TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'locked')),
  window_price INTEGER NOT NULL CHECK (window_price >= 0),
  distribution_price INTEGER NOT NULL CHECK (distribution_price >= 0),
  target_per_sack INTEGER NOT NULL CHECK (target_per_sack > 0),
  batch_size_kg REAL NOT NULL CHECK (batch_size_kg IN (37.5, 50)),
  locked_at TEXT,
  UNIQUE (bakery_id, date)
);

-- القطعيات: عدد العيش لكل جوال (seq = رقم الجوال)
CREATE TABLE sack_entries (
  id TEXT PRIMARY KEY,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  device_id TEXT,
  synced INTEGER NOT NULL DEFAULT 0,
  day_id TEXT NOT NULL REFERENCES days(id),
  seq INTEGER NOT NULL CHECK (seq > 0),
  loaves INTEGER NOT NULL CHECK (loaves >= 0),
  cancelled_at TEXT,
  UNIQUE (day_id, seq)
);

-- العجنات: الحجم الثابت وعددها، وصف إضافي لعجنة 25 كجم عند الحاجة
CREATE TABLE kneading_batches (
  id TEXT PRIMARY KEY,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  device_id TEXT,
  synced INTEGER NOT NULL DEFAULT 0,
  day_id TEXT NOT NULL REFERENCES days(id),
  size_kg REAL NOT NULL CHECK (size_kg IN (25, 37.5, 50)),
  batches INTEGER NOT NULL CHECK (batches > 0),
  cancelled_at TEXT,
  UNIQUE (day_id, size_kg)
);

-- ───────── التوزيع ─────────

CREATE TABLE distributors (
  id TEXT PRIMARY KEY,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  device_id TEXT,
  synced INTEGER NOT NULL DEFAULT 0,
  bakery_id TEXT NOT NULL REFERENCES bakeries(id),
  name TEXT NOT NULL,
  active INTEGER NOT NULL DEFAULT 1,
  cancelled_at TEXT,
  UNIQUE (bakery_id, name)
);

-- المستحق = loaves × days.distribution_price (يُحسب في المشهد v_distribution_lines)
-- سداد دين يوم سابق يُسجَّل في صف اليوم الحالي، فقد يزيد amount_paid عن مستحق ذلك اليوم
CREATE TABLE distributions (
  id TEXT PRIMARY KEY,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  device_id TEXT,
  synced INTEGER NOT NULL DEFAULT 0,
  day_id TEXT NOT NULL REFERENCES days(id),
  distributor_id TEXT NOT NULL REFERENCES distributors(id),
  loaves INTEGER NOT NULL CHECK (loaves >= 0),
  amount_paid INTEGER NOT NULL DEFAULT 0 CHECK (amount_paid >= 0),
  cancelled_at TEXT,
  UNIQUE (day_id, distributor_id)
);

-- ───────── المصروفات ─────────

-- المصروفات الثابتة اليومية: تُنسخ تلقائياً إلى كل يوم جديد
CREATE TABLE expense_templates (
  id TEXT PRIMARY KEY,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  device_id TEXT,
  synced INTEGER NOT NULL DEFAULT 0,
  bakery_id TEXT NOT NULL REFERENCES bakeries(id),
  name TEXT NOT NULL,
  amount INTEGER NOT NULL CHECK (amount >= 0),
  active INTEGER NOT NULL DEFAULT 1,
  cancelled_at TEXT
);

-- general: مصروف عام يُخصم من الوردية (ثابت أو متحرك)
-- agent_personal: مصروف شخصي للوكيل، يُجمع شهرياً ويُخصم من راتبه ولا يدخل حساب اليوم
CREATE TABLE expenses (
  id TEXT PRIMARY KEY,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  device_id TEXT,
  synced INTEGER NOT NULL DEFAULT 0,
  day_id TEXT NOT NULL REFERENCES days(id),
  scope TEXT NOT NULL DEFAULT 'general' CHECK (scope IN ('general', 'agent_personal')),
  kind TEXT CHECK (kind IN ('fixed', 'variable')),
  name TEXT NOT NULL,
  amount INTEGER NOT NULL CHECK (amount >= 0),
  cancelled_at TEXT,
  CHECK (scope = 'agent_personal' OR kind IS NOT NULL)
);

-- ───────── المخزون ─────────

CREATE TABLE stock_items (
  code TEXT PRIMARY KEY CHECK (code IN ('flour', 'yeast', 'gas')),
  name_ar TEXT NOT NULL,
  unit TEXT NOT NULL
);

INSERT INTO stock_items (code, name_ar, unit) VALUES
  ('flour', 'الدقيق', 'kg'),
  ('yeast', 'الخميرة', 'unit'),
  ('gas', 'الغاز', 'unit');

-- المتبقي = opening + incoming - outgoing - used (يُحسب في المشهد v_stock_closing)
-- الدقيق: outgoing = شوالات خرجت من المخبز، used = مجموع (حجم العجنة × عددها) من kneading_batches
-- opening لليوم الجديد = متبقي اليوم السابق (ينسخه التطبيق عند إنشاء اليوم)
CREATE TABLE stock_daily (
  id TEXT PRIMARY KEY,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  device_id TEXT,
  synced INTEGER NOT NULL DEFAULT 0,
  day_id TEXT NOT NULL REFERENCES days(id),
  item TEXT NOT NULL REFERENCES stock_items(code),
  opening REAL NOT NULL DEFAULT 0,
  incoming REAL NOT NULL DEFAULT 0,
  outgoing REAL NOT NULL DEFAULT 0,
  used REAL NOT NULL DEFAULT 0,
  cancelled_at TEXT,
  UNIQUE (day_id, item)
);

-- ───────── التوريدات والحسابات ─────────

-- توريدة البنكجي (role = bankaji) وتوريدة الوكيل لصاحب المخبز (role = agent)
-- التحويل البنكي يحتاج رقم العملية أو صورة الإشعار
CREATE TABLE remittances (
  id TEXT PRIMARY KEY,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  device_id TEXT,
  synced INTEGER NOT NULL DEFAULT 0,
  day_id TEXT NOT NULL REFERENCES days(id),
  role TEXT NOT NULL CHECK (role IN ('bankaji', 'agent')),
  amount INTEGER NOT NULL CHECK (amount >= 0),
  method TEXT NOT NULL CHECK (method IN ('cash', 'bank')),
  reference_no TEXT,
  receipt_image_path TEXT,
  cancelled_at TEXT,
  UNIQUE (day_id, role),
  CHECK (method = 'cash' OR reference_no IS NOT NULL OR receipt_image_path IS NOT NULL)
);

-- لقطة حساب اليوم، يكتبها التطبيق قبل قفل اليوم مباشرة:
--   window_loaves      = total_loaves - distributed_loaves
--   window_revenue     = window_loaves × window_price
--   distribution_total = distributed_loaves × distribution_price   (مبيعات توزيع اليوم الجديدة فقط)
--   bankaji_required   = window_revenue - general_expenses        (حساب البنكجي)
--   bankaji_diff       = bankaji_required - bankaji_remitted       (فرق البنكجي)
--   agent_required     = bankaji_required + distribution_total + agent_carry_in
--   agent_carry_out    = agent_required - agent_remitted           (ينتقل لحساب الغد)
CREATE TABLE day_accounts (
  id TEXT PRIMARY KEY,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  device_id TEXT,
  synced INTEGER NOT NULL DEFAULT 0,
  day_id TEXT NOT NULL UNIQUE REFERENCES days(id),
  total_loaves INTEGER NOT NULL,
  expected_loaves INTEGER NOT NULL,
  distributed_loaves INTEGER NOT NULL,
  window_loaves INTEGER NOT NULL,
  window_revenue INTEGER NOT NULL,
  distribution_total INTEGER NOT NULL,
  general_expenses INTEGER NOT NULL,
  bankaji_required INTEGER NOT NULL,
  bankaji_remitted INTEGER NOT NULL,
  bankaji_diff INTEGER NOT NULL,
  agent_carry_in INTEGER NOT NULL,
  agent_required INTEGER NOT NULL,
  agent_remitted INTEGER NOT NULL,
  agent_carry_out INTEGER NOT NULL,
  agent_personal_expenses INTEGER NOT NULL DEFAULT 0,
  cancelled_at TEXT
);

-- ───────── تعديل الأيام المقفلة (الرفض يتغلب) ─────────

-- لا يُفتح يوم مقفل إلا بموافقة الطرفين
CREATE TABLE edit_requests (
  id TEXT PRIMARY KEY,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  device_id TEXT,
  synced INTEGER NOT NULL DEFAULT 0,
  day_id TEXT NOT NULL REFERENCES days(id),
  agent_id TEXT REFERENCES agents(id),
  requested_by TEXT NOT NULL CHECK (requested_by IN ('owner', 'agent')),
  reason TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'applied')),
  owner_approved_at TEXT,
  agent_approved_at TEXT,
  applied_at TEXT,
  rejected_at TEXT,
  rejected_by TEXT CHECK (rejected_by IN ('owner', 'agent')),
  CHECK (status NOT IN ('approved', 'applied') OR (owner_approved_at IS NOT NULL AND agent_approved_at IS NOT NULL)),
  CHECK (status <> 'rejected' OR (rejected_at IS NOT NULL AND rejected_by IS NOT NULL))
);

-- سجل التعديلات: يُضاف إليه فقط ولا يُعدَّل ولا يُحذف
CREATE TABLE audit_log (
  id TEXT PRIMARY KEY,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  device_id TEXT,
  synced INTEGER NOT NULL DEFAULT 0,
  day_id TEXT NOT NULL REFERENCES days(id),
  agent_id TEXT REFERENCES agents(id),
  edit_request_id TEXT REFERENCES edit_requests(id),
  table_name TEXT NOT NULL,
  row_id TEXT NOT NULL,
  field TEXT,
  old_value TEXT,
  new_value TEXT,
  changed_by TEXT CHECK (changed_by IN ('owner', 'agent')),
  changed_at TEXT NOT NULL
);

CREATE TRIGGER trg_audit_no_update BEFORE UPDATE ON audit_log
BEGIN SELECT RAISE(ABORT, 'audit log is append-only'); END;

CREATE TRIGGER trg_audit_no_delete BEFORE DELETE ON audit_log
BEGIN SELECT RAISE(ABORT, 'audit log is append-only'); END;

-- ───────── مشاهد (Views) للعرض: تستثني الصفوف الملغاة ─────────

-- مجموع اليوم والمتوسط والفرق عن المفروض (مثل: زائد عن المفروض بـ 40 عيشة)
CREATE VIEW v_day_totals AS
SELECT d.id AS day_id,
       d.bakery_id,
       d.date,
       COUNT(s.id) AS sacks,
       COALESCE(SUM(s.loaves), 0) AS total_loaves,
       ROUND(AVG(s.loaves), 1) AS avg_per_sack,
       COUNT(s.id) * d.target_per_sack AS expected_loaves,
       COALESCE(SUM(s.loaves), 0) - COUNT(s.id) * d.target_per_sack AS diff_from_expected
FROM days d
LEFT JOIN sack_entries s ON s.day_id = d.id AND s.cancelled_at IS NULL
GROUP BY d.id;

-- جدول الموزعين لليوم: الكمية والمستحق والمسدد والمتبقي
CREATE VIEW v_distribution_lines AS
SELECT x.day_id,
       d.bakery_id,
       x.distributor_id,
       p.name,
       x.loaves,
       x.loaves * d.distribution_price AS amount_due,
       x.amount_paid,
       x.loaves * d.distribution_price - x.amount_paid AS remaining
FROM distributions x
JOIN distributors p ON p.id = x.distributor_id
JOIN days d ON d.id = x.day_id
WHERE x.cancelled_at IS NULL;

-- دين كل موزع عبر كل الأيام (للمتابعة فقط، فهو محسوب أصلاً ضمن رصيد الوكيل المرحَّل)
CREATE VIEW v_distributor_balances AS
SELECT d.bakery_id,
       x.distributor_id,
       p.name,
       SUM(x.loaves * d.distribution_price - x.amount_paid) AS balance
FROM distributions x
JOIN distributors p ON p.id = x.distributor_id
JOIN days d ON d.id = x.day_id
WHERE x.cancelled_at IS NULL
GROUP BY d.bakery_id, x.distributor_id;

CREATE VIEW v_stock_closing AS
SELECT day_id, item, opening, incoming, outgoing, used,
       opening + incoming - outgoing - used AS closing
FROM stock_daily
WHERE cancelled_at IS NULL;

-- حساب الشهر من لقطات الأيام، لكل وكيل في كل مخبز تقريره
CREATE VIEW v_month_summary AS
SELECT d.bakery_id,
       d.agent_id,
       substr(d.date, 1, 7) AS month,
       COUNT(*) AS days_count,
       SUM(a.total_loaves) AS total_loaves,
       SUM(a.window_revenue) AS window_revenue,
       SUM(a.distribution_total) AS distribution_total,
       SUM(a.general_expenses) AS general_expenses,
       SUM(a.bankaji_required) AS bankaji_required,
       SUM(a.bankaji_remitted) AS bankaji_remitted,
       SUM(a.agent_remitted) AS agent_remitted,
       SUM(a.agent_personal_expenses) AS agent_personal_expenses
FROM day_accounts a
JOIN days d ON d.id = a.day_id
WHERE a.cancelled_at IS NULL
GROUP BY d.bakery_id, d.agent_id, substr(d.date, 1, 7);

-- ───────── أقفال اليوم وعزل المخابز (تمنع التعديل حتى لو تجاوز أحد التطبيق) ─────────

-- لا يُعدَّل يوم مقفل
CREATE TRIGGER trg_days_locked_update BEFORE UPDATE ON days
WHEN OLD.status = 'locked' AND NEW.status = 'locked'
BEGIN SELECT RAISE(ABORT, 'day is locked'); END;

-- فتح يوم مقفل يحتاج طلباً معتمداً من الطرفين لم يُستعمل بعد (status = approved)
CREATE TRIGGER trg_days_unlock BEFORE UPDATE ON days
WHEN OLD.status = 'locked' AND NEW.status = 'open'
 AND NOT EXISTS (
   SELECT 1 FROM edit_requests
   WHERE day_id = OLD.id AND status = 'approved'
     AND owner_approved_at IS NOT NULL AND agent_approved_at IS NOT NULL
 )
BEGIN SELECT RAISE(ABORT, 'unlock needs approval of both'); END;

CREATE TRIGGER trg_days_no_delete BEFORE DELETE ON days
BEGIN SELECT RAISE(ABORT, 'rows are never deleted'); END;

-- لا يُنشأ يوم إلا لوكيل مُسنَد إلى هذا المخبز في ذلك التاريخ
-- (عند سحب بيانات السحابة على جهاز المالك يجب سحب agent_bakery قبل days)
CREATE TRIGGER trg_days_agent_assigned BEFORE INSERT ON days
WHEN NOT EXISTS (
  SELECT 1 FROM agent_bakery
  WHERE agent_id = NEW.agent_id AND bakery_id = NEW.bakery_id
    AND started_at <= NEW.date AND (ended_at IS NULL OR ended_at >= NEW.date)
)
BEGIN SELECT RAISE(ABORT, 'agent is not assigned to this bakery on this date'); END;

-- لا يُسجَّل توزيع على موزع من مخبز آخر
CREATE TRIGGER trg_distributions_same_bakery BEFORE INSERT ON distributions
WHEN (SELECT bakery_id FROM distributors WHERE id = NEW.distributor_id) <> (SELECT bakery_id FROM days WHERE id = NEW.day_id)
BEGIN SELECT RAISE(ABORT, 'distributor belongs to another bakery'); END;

-- الرفض يتغلب: عند تعيين rejected_at يصير الطلب مرفوضاً وتُمسح الموافقات، ولا تُقبل أي موافقة بعده
CREATE TRIGGER trg_edit_requests_rejection_clears AFTER UPDATE ON edit_requests
WHEN NEW.rejected_at IS NOT NULL
 AND (NEW.status <> 'rejected' OR NEW.owner_approved_at IS NOT NULL OR NEW.agent_approved_at IS NOT NULL)
BEGIN UPDATE edit_requests SET status = 'rejected', owner_approved_at = NULL, agent_approved_at = NULL WHERE id = NEW.id; END;

CREATE TRIGGER trg_edit_requests_rejection_wins BEFORE UPDATE ON edit_requests
WHEN OLD.rejected_at IS NOT NULL
 AND (NEW.rejected_at IS NULL OR NEW.status <> 'rejected' OR NEW.owner_approved_at IS NOT NULL OR NEW.agent_approved_at IS NOT NULL)
BEGIN SELECT RAISE(ABORT, 'request was rejected'); END;

-- الجداول اليومية: لا إضافة ولا تعديل بعد قفل اليوم، ولا حذف أبداً

CREATE TRIGGER trg_sack_entries_locked_ins BEFORE INSERT ON sack_entries
WHEN (SELECT status FROM days WHERE id = NEW.day_id) = 'locked'
BEGIN SELECT RAISE(ABORT, 'day is locked'); END;

CREATE TRIGGER trg_sack_entries_locked_upd BEFORE UPDATE ON sack_entries
WHEN (SELECT status FROM days WHERE id = OLD.day_id) = 'locked' OR (SELECT status FROM days WHERE id = NEW.day_id) = 'locked'
BEGIN SELECT RAISE(ABORT, 'day is locked'); END;

CREATE TRIGGER trg_sack_entries_no_delete BEFORE DELETE ON sack_entries
BEGIN SELECT RAISE(ABORT, 'rows are never deleted (use cancelled_at or ended_at)'); END;

CREATE TRIGGER trg_kneading_batches_locked_ins BEFORE INSERT ON kneading_batches
WHEN (SELECT status FROM days WHERE id = NEW.day_id) = 'locked'
BEGIN SELECT RAISE(ABORT, 'day is locked'); END;

CREATE TRIGGER trg_kneading_batches_locked_upd BEFORE UPDATE ON kneading_batches
WHEN (SELECT status FROM days WHERE id = OLD.day_id) = 'locked' OR (SELECT status FROM days WHERE id = NEW.day_id) = 'locked'
BEGIN SELECT RAISE(ABORT, 'day is locked'); END;

CREATE TRIGGER trg_kneading_batches_no_delete BEFORE DELETE ON kneading_batches
BEGIN SELECT RAISE(ABORT, 'rows are never deleted (use cancelled_at or ended_at)'); END;

CREATE TRIGGER trg_distributions_locked_ins BEFORE INSERT ON distributions
WHEN (SELECT status FROM days WHERE id = NEW.day_id) = 'locked'
BEGIN SELECT RAISE(ABORT, 'day is locked'); END;

CREATE TRIGGER trg_distributions_locked_upd BEFORE UPDATE ON distributions
WHEN (SELECT status FROM days WHERE id = OLD.day_id) = 'locked' OR (SELECT status FROM days WHERE id = NEW.day_id) = 'locked'
BEGIN SELECT RAISE(ABORT, 'day is locked'); END;

CREATE TRIGGER trg_distributions_no_delete BEFORE DELETE ON distributions
BEGIN SELECT RAISE(ABORT, 'rows are never deleted (use cancelled_at or ended_at)'); END;

CREATE TRIGGER trg_expenses_locked_ins BEFORE INSERT ON expenses
WHEN (SELECT status FROM days WHERE id = NEW.day_id) = 'locked'
BEGIN SELECT RAISE(ABORT, 'day is locked'); END;

CREATE TRIGGER trg_expenses_locked_upd BEFORE UPDATE ON expenses
WHEN (SELECT status FROM days WHERE id = OLD.day_id) = 'locked' OR (SELECT status FROM days WHERE id = NEW.day_id) = 'locked'
BEGIN SELECT RAISE(ABORT, 'day is locked'); END;

CREATE TRIGGER trg_expenses_no_delete BEFORE DELETE ON expenses
BEGIN SELECT RAISE(ABORT, 'rows are never deleted (use cancelled_at or ended_at)'); END;

CREATE TRIGGER trg_stock_daily_locked_ins BEFORE INSERT ON stock_daily
WHEN (SELECT status FROM days WHERE id = NEW.day_id) = 'locked'
BEGIN SELECT RAISE(ABORT, 'day is locked'); END;

CREATE TRIGGER trg_stock_daily_locked_upd BEFORE UPDATE ON stock_daily
WHEN (SELECT status FROM days WHERE id = OLD.day_id) = 'locked' OR (SELECT status FROM days WHERE id = NEW.day_id) = 'locked'
BEGIN SELECT RAISE(ABORT, 'day is locked'); END;

CREATE TRIGGER trg_stock_daily_no_delete BEFORE DELETE ON stock_daily
BEGIN SELECT RAISE(ABORT, 'rows are never deleted (use cancelled_at or ended_at)'); END;

CREATE TRIGGER trg_remittances_locked_ins BEFORE INSERT ON remittances
WHEN (SELECT status FROM days WHERE id = NEW.day_id) = 'locked'
BEGIN SELECT RAISE(ABORT, 'day is locked'); END;

CREATE TRIGGER trg_remittances_locked_upd BEFORE UPDATE ON remittances
WHEN (SELECT status FROM days WHERE id = OLD.day_id) = 'locked' OR (SELECT status FROM days WHERE id = NEW.day_id) = 'locked'
BEGIN SELECT RAISE(ABORT, 'day is locked'); END;

CREATE TRIGGER trg_remittances_no_delete BEFORE DELETE ON remittances
BEGIN SELECT RAISE(ABORT, 'rows are never deleted (use cancelled_at or ended_at)'); END;

CREATE TRIGGER trg_day_accounts_locked_ins BEFORE INSERT ON day_accounts
WHEN (SELECT status FROM days WHERE id = NEW.day_id) = 'locked'
BEGIN SELECT RAISE(ABORT, 'day is locked'); END;

CREATE TRIGGER trg_day_accounts_locked_upd BEFORE UPDATE ON day_accounts
WHEN (SELECT status FROM days WHERE id = OLD.day_id) = 'locked' OR (SELECT status FROM days WHERE id = NEW.day_id) = 'locked'
BEGIN SELECT RAISE(ABORT, 'day is locked'); END;

CREATE TRIGGER trg_day_accounts_no_delete BEFORE DELETE ON day_accounts
BEGIN SELECT RAISE(ABORT, 'rows are never deleted (use cancelled_at or ended_at)'); END;

-- بقية الجداول المتزامنة: لا حذف أبداً

CREATE TRIGGER trg_bakeries_no_delete BEFORE DELETE ON bakeries
BEGIN SELECT RAISE(ABORT, 'rows are never deleted (use cancelled_at or ended_at)'); END;

CREATE TRIGGER trg_agents_no_delete BEFORE DELETE ON agents
BEGIN SELECT RAISE(ABORT, 'rows are never deleted (use cancelled_at or ended_at)'); END;

CREATE TRIGGER trg_agent_bakery_no_delete BEFORE DELETE ON agent_bakery
BEGIN SELECT RAISE(ABORT, 'rows are never deleted (use cancelled_at or ended_at)'); END;

CREATE TRIGGER trg_settings_no_delete BEFORE DELETE ON settings
BEGIN SELECT RAISE(ABORT, 'rows are never deleted (use cancelled_at or ended_at)'); END;

CREATE TRIGGER trg_distributors_no_delete BEFORE DELETE ON distributors
BEGIN SELECT RAISE(ABORT, 'rows are never deleted (use cancelled_at or ended_at)'); END;

CREATE TRIGGER trg_expense_templates_no_delete BEFORE DELETE ON expense_templates
BEGIN SELECT RAISE(ABORT, 'rows are never deleted (use cancelled_at or ended_at)'); END;

CREATE TRIGGER trg_edit_requests_no_delete BEFORE DELETE ON edit_requests
BEGIN SELECT RAISE(ABORT, 'rows are never deleted (use cancelled_at or ended_at)'); END;

