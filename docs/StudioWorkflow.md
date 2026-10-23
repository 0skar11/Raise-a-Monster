# تعديل اللعبة والأنيميشن

افتح `RaiseAMonster_fixed.rbxlx`. داخل Workspace:

- `StudioWorld`: معاينة القواعد والمتجر ومناطق الوحوش قبل Run. تُزال عند التشغيل وتُبنى نسخة اللعب بالكود، لذلك تغييرات تصميم الماب الدائمة تكون في PlotService وZoneService ثم إعادة بناء المعاينة.
- `AnimationRigs`: كل الوحوش ومراحلها، موزعة خارج الماب لتسهيل التحديد. اختر Model داخل مجلد المنطقة ثم نوع الوحش ثم Baby / Teen / Adult، وافتح Animation Editor.

هذه الـrigs تُستخدم كقوالب اللعب عند Run. احفظ تعديلاتك بـCtrl+S وأنت خارج Play mode. النشر يكون من Studio؛ تحديث ملف محلي وحده لا ينشر اللعبة.

## أنيميشن منشور

داخل الـModel المطلوب أنشئ Folder اسمه `Animations`، وضع فيه Animation باسم `Idle` أو `Walk` أو `Attack`. ضع رابط الأنيميشن المنشور في AnimationId، مثل `rbxassetid://123456789`. يجب أن يملك صاحب التجربة صلاحية استخدام الأنيميشن. الحالات التي لا يوجد لها Animation تستخدم الحركة البرمجية الحالية.

## تحديث الكود في الملف الحقيقي

احفظ وأغلق الملف في Studio قبل تشغيل الأمر التالي من مجلد المشروع:

```powershell
& .\tools\UpdateGame.ps1
```

الأمر يبني مصدر Rojo، يحدّث السكربتات داخل `RaiseAMonster_fixed.rbxlx`، يحتفظ بتعديلات AnimationRigs المحفوظة، ويضع نسخة احتياطية في مجلد `.codex-backups` بجوار المشروع. أعد فتح الملف بعد اكتمال الأمر.

## مزامنة Rojo

شغّل `rojo serve` من مجلد المشروع، ثم Connect من إضافة Rojo في وضع Edit. Rojo يقرأ الملفات المحلية؛ تحديث GitHub يحتاج `git pull` أولاً. بعد تغيير السكربتات أوقف Play ثم شغله مرة أخرى لإعادة تهيئة الخدمات والـModuleScripts.

قبل إعادة الاتصال بـRojo بعد تعديل rigs في Studio، صدّر التعديلات إلى المصدر حتى لا تستبدلها نسخة assets القديمة:

```powershell
& "$env:LOCALAPPDATA\RaiseAMonsterTools\lune.exe" run tools/export-animation-rigs.luau RaiseAMonster_fixed.rbxlx
& "$env:USERPROFILE\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe" tools/rojo-xml-compat.py
```

## إعادة بناء معاينة الماب

```powershell
rojo build -o "$env:TEMP\RaiseAMonster-preview-input.rbxlx"
& "$env:LOCALAPPDATA\RaiseAMonsterTools\lune.exe" run tools/bake-studio-world.luau "$env:TEMP\RaiseAMonster-preview-input.rbxlx"
& "$env:USERPROFILE\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe" tools/rojo-xml-compat.py
& .\tools\UpdateGame.ps1
```

توليد المعاينة يعيد توليد ملف `assets/AnimationRigs.rbxmx` أيضاً؛ صدّر واحفظ تعديلات الأنيميشن قبل هذه العملية. جبال Terrain الطبيعية تُولد وقت اللعب؛ معاينة StudioWorld تعرض هندسة الماب والوحوش.
