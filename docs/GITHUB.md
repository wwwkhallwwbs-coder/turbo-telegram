# المتابعة على GitHub

## 1. إنشاء المستودع

1. سجّل في github.com إن لم يكن عندك حساب.
2. **New repository** ثم اختر اسماً (مثلاً `makhbazak`).
3. اختر **Private** (فيه المواصفة والتصميم).
4. اترك خيارات README و.gitignore والترخيص **غير مفعلة**، ليكون المستودع فارغاً.

> انسخ الرابط من شريط العنوان في صفحة المستودع كما هو، ولا تكتبه من ذاكرتك. GitHub قد يعدّل الأسماء التي تنتهي بنقطة أو تحوي رموزاً.

## 2. رفع الكود

ربط GitHub بـ Claude (جلسات Claude Code السحابية) متاح في الخطط المدفوعة فقط، ولا يظهر في قائمة الموصّلات في الخطة المجانية. لذلك الرفع يدوي بإحدى الطريقتين.

### أ. من حاسوب (الأسرع، دقيقتان)

```bash
unzip makhbazak.zip && cd makhbazak
git init -b main
git add .
git commit -m "الهيكل الأول: المخطط والمعادلات والاختبارات وCI"
git remote add origin https://github.com/<اسمك>/<اسم-المستودع>.git
git push -u origin main
```

عند الطلب، اسم المستخدم هو اسم حسابك على GitHub، وكلمة المرور هي **Personal Access Token** وليست كلمة مرور الحساب (GitHub: Settings ← Developer settings ← Personal access tokens، صلاحية `repo` و`workflow`). لا ترسل هذا الرمز لأحد، ولا تلصقه في أي محادثة.

### ب. بدون حاسوب: Codespaces من المتصفح

1. في صفحة المستودع الفارغ اضغط **Add a README file** واحفظ (لإنشاء أول commit).
2. **Code ← Codespaces ← Create codespace on main**. تفتح بيئة VS Code في المتصفح.
3. اسحب `makhbazak.zip` إلى قائمة الملفات على اليسار (أو كليك يمين ← Upload).
4. في الطرفية بالأسفل:

```bash
unzip -o makhbazak.zip
cp -r makhbazak/. . && rm -rf makhbazak makhbazak.zip
git add -A
git commit -m "الهيكل الأول: المخطط والمعادلات والاختبارات وCI"
git push
```

Codespaces لها رصيد مجاني شهري لحسابات GitHub الشخصية، وتعمل بأفضل شكل من شاشة كبيرة.

### ب2. من الهاتف: فك الضغط بواسطة GitHub Actions

GitHub لا يفك ملف zip عند الرفع، لكن يمكن لـ workflow صغير أن يفكه عنك:

1. أنشئ ملف الفك مرة واحدة: **Actions ← New workflow ← set up a workflow yourself**. يفتح محرراً بمسار جاهز `.github/workflows/main.yml`. غيّر اسم الملف إلى `unpack.yml` (الجزء الأخير فقط) والصق محتوى `ci/unpack.yml` من هذا المستودع. لا تكتب المسار `.github/...` بيدك على الهاتف، فقد تُحذف النقطة الأولى فيُنشأ مجلد `github` خاطئ.
2. **Add file ← Upload files**: ارفع `makhbazak.zip` كما هو في جذر المستودع.
3. تبويب **Actions ← Unpack ← Run workflow**. يفك الملفات ثم يحاول تشغيل بناء Android وحده.
   - **تأكد دائماً:** ادخل Actions وانظر أول سطر في قائمة التشغيلات: يجب أن يكون تشغيل «Android» جديداً بوقت قريب ورسالة «فك ضغط الإصدار المرفوع». المرفوعات التي يقوم بها Unpack بصلاحية `GITHUB_TOKEN` **لا تشغّل البناء تلقائياً** (قيد من GitHub). فإن لم يظهر تشغيل جديد: **Actions ← Android (من القائمة اليسرى) ← Run workflow ← Run workflow**.
   - علامات ✓ الخضراء القديمة تخص البناء القديم. حمّل APK من **آخر** تشغيل فقط، وتحقق من رقم النسخة المكتوب أسفل شاشة البداية (نسخ التجربة).
4. ملف `.github/workflows/android.yml` لا يستطيع Unpack تعديله (GitHub لا يسمح لـ workflow بتغيير ملفات workflows). فإذا تغيّر في إصدار جديد، افتح الملف الموجود بالقلم والصق فيه محتوى `ci/android.yml` الجديد.

نفس الطريقة تصلح لكل تحديث لاحق: ارفع zip جديداً بنفس الاسم ثم شغّل Unpack. لا تحفظ تعديلات أخرى في المستودع أثناء تشغيله. إذا فشل بسبب الصلاحيات: **Settings ← Actions ← General ← Workflow permissions ← Read and write**.

### ج. ملفات صغيرة فقط

للتعديلات الصغيرة (إصلاح سطر أو ملف) استخدم زر القلم في صفحة الملف على GitHub، أو **Add file ← Create new file** واكتب المسار كاملاً (`lib/core/x.dart`). لا يصلح هذا لرفع المشروع كله، لأن GitHub لا يفك ملف zip ولا يرفع مجلدات من متصفح الهاتف.

## 3. أول بناء

عند أول رفع يعمل الـ workflow **Android** وحده:

- **schema:** يشغّل `tools/verify_schema.py` على SQLite.
- **build:** يولّد مجلد أندرويد، ثم `flutter analyze` و`flutter test` و`flutter build apk --debug`.

النتيجة في تبويب **Actions**، والـ APK في الملف المرفق `makhbazak-debug-apk` أسفل صفحة التشغيل.

> الكود الخاص بـ Flutter كُتب دون إمكانية تشغيل المترجم في بيئة الكتابة، فأول تشغيل هو أول فحص حقيقي له. إذا فشل فألصق سجل الخطأ في المحادثة ليُصلح.

## 4. أسلوب العمل بعد ذلك

- كل مهمة على **فرع** جديد (`feature/production-screen` مثلاً) ثم **Pull Request**.
- لا يُدمج الطلب إلا بعد نجاح الـ CI (علامة خضراء).
- فعّل حماية الفرع `main`: **Settings → Branches → Add rule → Require status checks to pass**.
- أي تغيير في معادلة أو جدول يرافقه تعديل الاختبار، فلا يتسرب خطأ حسابي.

## 5. الأسرار

لا يُرفع أبداً: ملف التوقيع (`*.jks`)، ومفتاح توقيع رموز التفعيل الخاص، وكلمات المرور، ورمز GitHub الشخصي. تُحفظ في **Settings → Secrets and variables → Actions** عند الحاجة لتوقيع الإصدار النهائي.

## 6. تطبيق Flutter على هاتفك

نزّل `app-debug.apk` من الملف المرفق، وفعّل «التثبيت من مصادر غير معروفة» للمتصفح أو مدير الملفات. هذا APK للتجربة فقط. النسخة التي تُنشر في المتجر تحتاج توقيعاً وإصداراً (release) لاحقاً.
