#!/usr/bin/env python3
"""يتحقق من assets/db/schema.sql على SQLite حقيقية.

يجرّب: أمثلة المواصفة الرقمية (§4)، أقفال الأيام، الحذف الممنوع، الرفض يتغلب،
عزل المخابز، وتطابق مقسّم السكريبت مع ما يفعله تطبيق Dart.
التشغيل: python3 -I tools/verify_schema.py
"""
import re
import sqlite3
import sys
from pathlib import Path

SCHEMA = Path(__file__).resolve().parent.parent / "assets" / "db" / "schema.sql"


def split_script(script):
    """نفس منطق lib/core/sql_script.dart: يقسم السكريبت إلى جمل، ويعتبر END; نهاية الـ trigger."""
    statements, buf, in_trigger = [], [], False
    trigger_end = re.compile(r"END;\s*$", re.I)
    for raw in script.split("\n"):
        line = raw.strip()
        if not line or line.startswith("--"):
            continue
        buf.append(raw)
        if line.upper().startswith("CREATE TRIGGER"):
            in_trigger = True
        done = bool(trigger_end.search(line)) if in_trigger else line.endswith(";")
        if done:
            statement = "\n".join(buf).strip()
            buf, in_trigger = [], False
            if not statement.upper().startswith("PRAGMA"):
                statements.append(statement)
    assert not buf, f"unterminated statement: {buf}"
    return statements


def connect():
    db = sqlite3.connect(":memory:")
    db.execute("PRAGMA foreign_keys = ON")
    for statement in split_script(SCHEMA.read_text(encoding="utf-8")):
        db.execute(statement)
    return db


def fresh():
    db = connect()
    db.execute("INSERT INTO bakeries(id,name) VALUES('b1','مخبز أ'),('b2','مخبز ب')")
    db.execute("INSERT INTO agents(id,name) VALUES('a1','وكيل 1'),('a2','وكيل 2')")
    db.execute(
        "INSERT INTO agent_bakery(id,agent_id,bakery_id,started_at) "
        "VALUES('ab1','a1','b1','2026-01-01'),('ab2','a2','b2','2026-01-01')"
    )
    return db


def add_day(db, day="d1", date="2026-11-19", bakery="b1", agent="a1"):
    db.execute(
        "INSERT INTO days(id,bakery_id,agent_id,date,window_price,distribution_price,"
        "target_per_sack,batch_size_kg) VALUES(?,?,?,?,100,90,900,50)",
        (day, bakery, agent, date),
    )


def blocked(db, sql, *params):
    try:
        db.execute(sql, params)
    except sqlite3.IntegrityError:
        return
    raise AssertionError("not blocked: " + sql)


LOAVES = [890, 880, 920, 905, 915, 898, 910, 925, 897, 900]


def seed_spec_day(db, day="d1"):
    """يملأ يوماً بأرقام المواصفة §4 (الشاشات التجريبية)."""
    for i, v in enumerate(LOAVES, 1):
        db.execute("INSERT INTO sack_entries(id,day_id,seq,loaves) VALUES(?,?,?,?)", (f"s{i}", day, i, v))
    db.execute("INSERT INTO kneading_batches(id,day_id,size_kg,batches) VALUES('k1',?,50,10)", (day,))
    for i, (name, loaves, paid) in enumerate([("أ", 250, 22500), ("ب", 300, 20000), ("ج", 180, 10000)], 1):
        db.execute("INSERT INTO distributors(id,bakery_id,name) VALUES(?,?,?)", (f"p{i}", "b1", name))
        db.execute(
            "INSERT INTO distributions(id,day_id,distributor_id,loaves,amount_paid) VALUES(?,?,?,?,?)",
            (f"x{i}", day, f"p{i}", loaves, paid),
        )
    general = [("fixed", 150000), ("fixed", 20000), ("fixed", 50000), ("variable", 15000), ("variable", 10000)]
    for i, (kind, amount) in enumerate(general, 1):
        db.execute(
            "INSERT INTO expenses(id,day_id,scope,kind,name,amount) VALUES(?,?,'general',?,'بند',?)",
            (f"e{i}", day, kind, amount),
        )
    for i in range(7):
        db.execute(
            "INSERT INTO expenses(id,day_id,scope,name,amount) VALUES(?,?,'agent_personal','شخصي',12000)",
            (f"pe{i}", day),
        )
    db.execute("INSERT INTO remittances(id,day_id,role,amount,method,reference_no) VALUES('r1',?,'bankaji',500000,'bank','TX1')", (day,))
    db.execute("INSERT INTO remittances(id,day_id,role,amount,method,reference_no) VALUES('r2',?,'agent',600000,'bank','TX2')", (day,))
    for item, opening, incoming, outgoing, used in [
        ("flour", 2000, 1000, 100, 500),  # 40 شوال + 20 − 2 − 10 عجنات
        ("yeast", 12, 0, 0, 3),
        ("gas", 6, 0, 0, 1),
    ]:
        db.execute(
            "INSERT INTO stock_daily(id,day_id,item,opening,incoming,outgoing,used) VALUES(?,?,?,?,?,?,?)",
            (f"t-{item}", day, item, opening, incoming, outgoing, used),
        )


def insert_account(db, day="d1"):
    db.execute(
        "INSERT INTO day_accounts(id,day_id,total_loaves,expected_loaves,distributed_loaves,window_loaves,"
        "window_revenue,distribution_total,general_expenses,bankaji_required,bankaji_remitted,bankaji_diff,"
        "agent_carry_in,agent_required,agent_remitted,agent_carry_out,agent_personal_expenses) "
        "VALUES('a-'||?,?,9040,9000,730,8310,831000,65700,245000,586000,500000,86000,0,651700,600000,51700,84000)",
        (day, day),
    )


# ───────── الاختبارات ─────────


def test_spec_examples():
    db = fresh()
    add_day(db)
    seed_spec_day(db)
    assert db.execute(
        "SELECT sacks,total_loaves,avg_per_sack,expected_loaves,diff_from_expected FROM v_day_totals"
    ).fetchone() == (10, 9040, 904.0, 9000, 40)  # §4.1
    lines = db.execute(
        "SELECT name,loaves,amount_due,amount_paid,remaining FROM v_distribution_lines ORDER BY name"
    ).fetchall()
    assert lines == [("أ", 250, 22500, 22500, 0), ("ب", 300, 27000, 20000, 7000), ("ج", 180, 16200, 10000, 6200)]
    assert sum(r[1] for r in lines) == 730 and sum(r[2] for r in lines) == 65700
    assert sum(r[3] for r in lines) == 52500 and sum(r[4] for r in lines) == 13200  # §4.2
    general = db.execute("SELECT SUM(amount) FROM expenses WHERE scope='general'").fetchone()[0]
    personal = db.execute("SELECT SUM(amount), COUNT(*) FROM expenses WHERE scope='agent_personal'").fetchone()
    assert general == 245000 and personal == (84000, 7)  # §4.3
    stock = dict(db.execute("SELECT item, closing FROM v_stock_closing").fetchall())
    assert stock == {"flour": 2400.0, "yeast": 9.0, "gas": 5.0}  # §4.4 (2400 كجم = 48 شوال)
    window_revenue = (9040 - 730) * 100
    bankaji = window_revenue - general
    agent_required = bankaji + 730 * 90 + 0
    assert (window_revenue, bankaji, bankaji - 500000) == (831000, 586000, 86000)
    assert (agent_required, agent_required - 600000) == (651700, 51700)  # §4.5
    insert_account(db)
    db.execute("UPDATE days SET status='locked', locked_at='t' WHERE id='d1'")
    row = db.execute(
        "SELECT bakery_id,agent_id,month,days_count,window_revenue,agent_personal_expenses FROM v_month_summary"
    ).fetchone()
    assert row == ("b1", "a1", "2026-11", 1, 831000, 84000)


def test_bank_remittance_needs_reference():
    db = fresh()
    add_day(db)
    blocked(db, "INSERT INTO remittances(id,day_id,role,amount,method) VALUES('r','d1','bankaji',1,'bank')")
    db.execute("INSERT INTO remittances(id,day_id,role,amount,method) VALUES('r','d1','bankaji',1,'cash')")


def test_locked_day_is_frozen():
    db = fresh()
    add_day(db)
    seed_spec_day(db)
    insert_account(db)
    db.execute("UPDATE days SET status='locked', locked_at='t' WHERE id='d1'")
    blocked(db, "INSERT INTO sack_entries(id,day_id,seq,loaves) VALUES('z','d1',11,900)")
    blocked(db, "UPDATE sack_entries SET loaves=1 WHERE id='s1'")
    blocked(db, "UPDATE sack_entries SET cancelled_at='x' WHERE id='s1'")
    blocked(db, "UPDATE days SET window_price=1 WHERE id='d1'")
    blocked(db, "UPDATE days SET status='open' WHERE id='d1'")  # بدون موافقة


def test_no_physical_delete_and_cancel_instead():
    db = fresh()
    add_day(db)
    seed_spec_day(db)
    for table, where in [
        ("sack_entries", "id='s1'"), ("kneading_batches", "id='k1'"), ("distributions", "id='x1'"),
        ("expenses", "id='e1'"), ("stock_daily", "id='t-gas'"), ("remittances", "id='r1'"),
        ("distributors", "id='p1'"), ("days", "id='d1'"), ("bakeries", "id='b1'"),
        ("agents", "id='a1'"), ("agent_bakery", "id='ab1'"),
    ]:
        blocked(db, f"DELETE FROM {table} WHERE {where}")
    db.execute("UPDATE sack_entries SET cancelled_at='t' WHERE id='s10'")
    assert db.execute("SELECT sacks,total_loaves FROM v_day_totals").fetchone() == (9, 8140)
    db.execute("UPDATE distributions SET cancelled_at='t' WHERE id='x3'")
    assert len(db.execute("SELECT * FROM v_distribution_lines").fetchall()) == 2


def test_edit_request_flow_and_rejection_wins():
    db = fresh()
    add_day(db)
    seed_spec_day(db)
    insert_account(db)
    db.execute("UPDATE days SET status='locked', locked_at='t' WHERE id='d1'")
    # موافقة واحدة لا تكفي
    db.execute("INSERT INTO edit_requests(id,day_id,agent_id,requested_by,reason,owner_approved_at) VALUES('q1','d1','a1','agent','خطأ','t')")
    blocked(db, "UPDATE days SET status='open' WHERE id='d1'")
    blocked(db, "UPDATE edit_requests SET status='approved' WHERE id='q1'")
    # الرفض يتغلب ويمسح الموافقات
    blocked(db, "UPDATE edit_requests SET rejected_at='t' WHERE id='q1'")  # يلزم rejected_by مع status=rejected فقط
    db.execute("UPDATE edit_requests SET rejected_at='t', rejected_by='owner' WHERE id='q1'")
    assert db.execute("SELECT status,owner_approved_at,agent_approved_at FROM edit_requests WHERE id='q1'").fetchone() == ("rejected", None, None)
    blocked(db, "UPDATE edit_requests SET owner_approved_at='t', agent_approved_at='t', status='approved' WHERE id='q1'")
    blocked(db, "UPDATE edit_requests SET rejected_at=NULL WHERE id='q1'")
    blocked(db, "UPDATE days SET status='open' WHERE id='d1'")
    # طلب معتمد من الطرفين يفتح اليوم مرة واحدة فقط
    db.execute("INSERT INTO edit_requests(id,day_id,agent_id,requested_by,reason,owner_approved_at,agent_approved_at,status) VALUES('q2','d1','a1','agent','خطأ','t','t','approved')")
    db.execute("UPDATE days SET status='open' WHERE id='d1'")
    db.execute("UPDATE sack_entries SET loaves=891 WHERE id='s1'")
    db.execute(
        "INSERT INTO audit_log(id,day_id,agent_id,edit_request_id,table_name,row_id,field,old_value,new_value,changed_by,changed_at) "
        "VALUES('l1','d1','a1','q2','sack_entries','s1','loaves','890','891','agent','t')"
    )
    db.execute("UPDATE days SET status='locked' WHERE id='d1'")
    db.execute("UPDATE edit_requests SET status='applied', applied_at='t' WHERE id='q2'")
    blocked(db, "UPDATE days SET status='open' WHERE id='d1'")
    blocked(db, "UPDATE audit_log SET new_value='1' WHERE id='l1'")
    blocked(db, "DELETE FROM audit_log WHERE id='l1'")
    blocked(db, "DELETE FROM edit_requests WHERE id='q2'")


def test_bakery_isolation_and_agent_assignment():
    db = fresh()
    # لا وكيلان نشطان على نفس المخبز، ولا وكيل نشط على مخبزين
    blocked(db, "INSERT INTO agent_bakery(id,agent_id,bakery_id,started_at) VALUES('x1','a2','b1','2026-02-01')")
    blocked(db, "INSERT INTO agent_bakery(id,agent_id,bakery_id,started_at) VALUES('x2','a1','b2','2026-02-01')")
    # نفس التاريخ في مخبزين مختلفين مسموح، وفي نفس المخبز ممنوع
    add_day(db, "d1", "2026-11-19", "b1", "a1")
    add_day(db, "d2", "2026-11-19", "b2", "a2")
    blocked(db, "INSERT INTO days(id,bakery_id,agent_id,date,window_price,distribution_price,target_per_sack,batch_size_kg) VALUES('d3','b1','a1','2026-11-19',1,1,1,50)")
    # وكيل غير مُسنَد إلى المخبز لا ينشئ يوماً
    blocked(db, "INSERT INTO days(id,bakery_id,agent_id,date,window_price,distribution_price,target_per_sack,batch_size_kg) VALUES('d4','b1','a2','2026-11-20',1,1,1,50)")
    # قفل يوم في مخبز لا يؤثر على الآخر
    db.execute("UPDATE days SET status='locked', locked_at='t' WHERE id='d1'")
    db.execute("INSERT INTO sack_entries(id,day_id,seq,loaves) VALUES('o1','d2',1,900)")
    # موزع من مخبز آخر ممنوع
    db.execute("INSERT INTO distributors(id,bakery_id,name) VALUES('pb','b2','موزع ب')")
    blocked(db, "INSERT INTO distributions(id,day_id,distributor_id,loaves) VALUES('xb','d1','pb',10)")
    # استبدال الوكيل: ينتهي القديم ويبدأ الجديد في يوم جديد
    db.execute("UPDATE agent_bakery SET ended_at='2026-11-30' WHERE id='ab1'")
    db.execute("INSERT INTO agents(id,name) VALUES('a3','وكيل جديد')")
    db.execute("INSERT INTO agent_bakery(id,agent_id,bakery_id,started_at) VALUES('ab3','a3','b1','2026-12-01')")
    blocked(db, "INSERT INTO days(id,bakery_id,agent_id,date,window_price,distribution_price,target_per_sack,batch_size_kg) VALUES('d5','b1','a1','2026-12-02',1,1,1,50)")
    db.execute("INSERT INTO days(id,bakery_id,agent_id,date,window_price,distribution_price,target_per_sack,batch_size_kg) VALUES('d6','b1','a3','2026-12-02',1,1,1,50)")
    # جهاز الوكيل يلزمه مخبز ووكيل
    blocked(db, "INSERT INTO device(id,role,activated_at,activation_code_hash) VALUES('dev','agent','t','h')")
    db.execute("INSERT INTO device(id,role,bakery_id,agent_id,activated_at,activation_code_hash) VALUES('dev','agent','b1','a3','t','h')")


def test_distributor_balance_carries_over_days():
    db = fresh()
    add_day(db, "d1", "2026-11-19")
    seed_spec_day(db, "d1")
    add_day(db, "d2", "2026-11-20")
    # اليوم التالي: الموزع ب يسدد 7000 من دين الأمس بدون كمية جديدة
    db.execute("INSERT INTO distributions(id,day_id,distributor_id,loaves,amount_paid) VALUES('y2','d2','p2',0,7000)")
    balances = dict(db.execute("SELECT name, balance FROM v_distributor_balances").fetchall())
    assert balances == {"أ": 0, "ب": 0, "ج": 6200}


def test_splitter_matches_executescript():
    sql = SCHEMA.read_text(encoding="utf-8")
    a = sqlite3.connect(":memory:")
    a.executescript(sql)
    b = connect()
    count = lambda d, t: d.execute("SELECT COUNT(*) FROM sqlite_master WHERE type=?", (t,)).fetchone()[0]
    for kind in ("table", "trigger", "view", "index"):
        assert count(a, kind) == count(b, kind), kind
    inline = [l for l in sql.split("\n") if "--" in l and not l.strip().startswith("--")]
    assert not inline, inline  # الـ splitter لا يدعم تعليقات داخل الجملة


def main():
    tests = [(n, f) for n, f in sorted(globals().items()) if n.startswith("test_") and callable(f)]
    failed = 0
    for name, fn in tests:
        try:
            fn()
            print("PASS", name)
        except Exception as exc:  # noqa: BLE001
            failed += 1
            print("FAIL", name, "->", repr(exc))
    print(f"{len(tests) - failed}/{len(tests)} passed (sqlite {sqlite3.sqlite_version})")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
