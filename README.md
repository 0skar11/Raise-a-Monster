# 🥚 Raise a Monster (Roblox)

لعبة Roblox: تفقس بيض، تربي وحوش وتطورها لحد ما تبقى أسطورية، تجمع فلوس، وتسرق وحوش اللاعبين التانيين (بستايل Steal a Brainrot).

خطة اللعبة بالتفصيل في [`docs/GameDesign.md`](docs/GameDesign.md).

---

## 🚀 الطريقة الأسهل: افتح الماب الجاهزة

1. نزّل الريبو:
   - من GitHub افتح برانش `claude/laughing-bell-h5hg6n`، ودوس **Code ← Download ZIP**، وفك الضغط في `D:\downloads\raise a monster`.
   - أو لو عندك Git:
     ```
     git clone -b claude/laughing-bell-h5hg6n https://github.com/0skar11/Raise-a-Monster.git "D:\downloads\raise a monster"
     ```
2. افتح ملف **`RaiseAMonster.rbxlx`** بـ Roblox Studio (دبل كليك عليه).
3. دوس **Play** ▶️ وجرّب.

> لتجربة السرقة: من تبويب **Test** اختار **Clients and Servers** وخلّي عدد اللاعبين 2، ودوس **Start**.

### عشان الحفظ يشتغل
الحفظ بيستخدم DataStore، وده مش بيشتغل غير لما اللعبة تتنشر:
1. **File ← Publish to Roblox**.
2. **Home ← Game Settings ← Security** وفعّل **Enable Studio Access to API Services**.

من غير الخطوتين دول اللعبة هتشتغل عادي، بس التقدم مش هيتحفظ.

---

## 🛠️ طريقة المطورين (Rojo)
الطريقة دي أحسن لو هتعدّل في الكود كتير، لأن أي تعديل في الملفات بيوصل لـ Studio على طول.

1. نزّل [Rokit](https://github.com/rojo-rbx/rokit) واكتب في فولدر المشروع:
   ```
   rokit install
   ```
   (أو نزّل [Rojo 7.4.4](https://github.com/rojo-rbx/rojo/releases) مباشرة.)
2. نزّل **Rojo Plugin** في Roblox Studio من الـ Toolbox أو بالأمر `rojo plugin install`.
3. في فولدر المشروع:
   ```
   rojo serve
   ```
4. في Studio افتح Baseplate جديد ← تبويب **Plugins ← Rojo ← Connect**.

لو عدّلت في الكود وعايز تعمل ملف ماب جديد:
```
rojo build -o RaiseAMonster.rbxlx
```
أو من غير Rojo خالص (محتاج Node.js بس):
```
node tools/build-place.js
```

---

## 🎮 إزاي تلعب
| الحاجة | تعمل إيه |
|---|---|
| 🥚 **Egg Shop** | المتجر في الساحة قدام القواعد (دوس **E**) أو زرار **Shop** في الشمال |
| 🗺️ **مناطق الوحوش** | امشي في الطريق ناحية المناطق؛ كل ما تبعد الوحوش بتصعب وبتبقى أندر |
| ⚔️ **الوحش الأم** | قرّب منها ودوس **E (Attack)** كذا مرة. ضربتك بتقوى كل ما وحوشك تنتج أكتر، وهي بتضرب اللي جنبها |
| 🐾 **الصغار** | بعد ما الأم تموت، دوس مطوّل على **E (Take)** على أي صغير وهيروح قاعدتك (لازم تكون ضربت الأم) |
| 🔄 **التجديد** | كل 10 دقايق الأعشاش بتتجدد بوحوش تانية، والعداد مكتوب على بوابة كل منطقة |
| 🐣 **الفقس** | البيضة بتتحط في قاعدتك وبتفقس بعد العداد |
| 🍖 **التربية** | قرّب من وحشك ودوس **E (Care)** ← Feed / Play / Sell |
| 💰 **الفلوس** | الوحوش بتنتج فلوس، اقف على المربع الأخضر في قاعدتك عشان تجمعها |
| 🦹 **السرقة** | مقفولة دلوقتي (`Config.Steal.Enabled = false`). لما ترجع: ادخل قاعدة حد ودوس مطوّل على **F (Steal)** واجري على قاعدتك |
| 🛡️ **الحماية** | زرار **Lock Base** الأحمر في قاعدتك، أو الحق الحرامي والمسه |
| ⬆️ **Upgrades** | Slots زيادة، وقفل بيدوم أكتر |

---

## 🎬 للـ Animator: الوحوش جاهزة في الماب
فيه 50 وحش (5 مناطق × 10)، وكل واحد ليه 3 مراحل (Baby / Teen / Adult)، وكلهم **Rig** معمولين من Parts ومتوصلين بـ **Motor6D**.

**إزاي توصلهم:**
1. نزّل الريبو من GitHub وافتح **`RaiseAMonster.rbxlx`** بـ Roblox Studio.
2. هتلاقي الوحوش في **Explorer ← ServerStorage ← MonsterModels ← <المنطقة> ← <رقم_الوحش> ← Baby / Teen / Adult**.
3. اسحب أي واحد لـ **Workspace**، واختاره، وافتح **Avatar ← Animation Editor**.

كل Rig فيه:
- `HumanoidRootPart`، وهو الـ PrimaryPart (مخفي ومثبّت).
- `AnimationController` جواه `Animator`.
- Motor6D بين أجزاء الجسم (Body، Head، Jaw، Legs، Arms، Wings، Tail…)، والتفاصيل ملزوقة (Weld) في العضمة بتاعتها.

**الأنيميشن جوه اللعبة:**
- كل وحش بيتحرك لوحده بالكود (`src/shared/MonsterAnimator.luau`): Idle وWalk وAttack، على حسب الـ Attribute اسمه `AnimState`.
- لو عايز تستخدم أنيميشن عملته بنفسك، حط الـ Attribute `Procedural = false` على الموديل، وشغّل الـ AnimationTrack بتاعك على الـ `Animator`.

**الملفات:**
| الملف | فيه إيه |
|---|---|
| `assets/MonsterModels.rbxmx` | الـ 150 Rig (اللي بيتحطوا في `ServerStorage.MonsterModels`) |
| `src/shared/MonsterAnimator.luau` | الأنيميشن بالكود (Idle / Walk / Attack) |
| `src/client/MonsterAnimate.luau` | بيشغّل الأنيميشن على الكلاينت لكل موديل عليه Tag اسمه `Monster` |
| `tools/GrowAMonster_RiggedGenerator.lua` | السكريبت اللي بيبني الوحوش من الأول |

**لو عدّلت شكل الوحوش:**
1. شغّل `tools/GrowAMonster_RiggedGenerator.lua` من الـ Command Bar في Place فاضي.
2. دوس كليك يمين على `ServerStorage.MonsterModels` واختار **Save to File** بصيغة **.rbxmx**، واحفظه مكان `assets/MonsterModels.rbxmx`.
3. ابني الماب تاني: `node tools/build-place.js` (أو `rojo build -o RaiseAMonster.rbxlx`).

---

## 📁 هيكل المشروع
```
default.project.json      ← إعدادات Rojo
RaiseAMonster.rbxlx       ← الماب الجاهزة (اتعملت بـ rojo build)
src/
  shared/   → ReplicatedStorage.Shared
    Config.luau        ← كل أرقام اللعبة: الأسعار والوحوش والبيض والتوازن
    MonsterMath.luau   ← حسابات الإنتاج والتطور
    Remotes.luau       ← RemoteEvents
  server/   → ServerScriptService.Server
    init.server.luau   ← تشغيل السيرفر
    DataService.luau   ← الحفظ
    PlotService.luau   ← الماب والقواعد وشكل الوحوش
    MonsterService.luau← البيض والتربية والاقتصاد
    StealService.luau  ← السرقة
  client/   → StarterPlayerScripts.Client
    init.client.luau   ← منطق الواجهة
    UI.luau            ← بناء الواجهة
docs/GameDesign.md        ← خطة اللعبة
```

عايز تغيّر الأسعار أو تزوّد وحش جديد؟ كل ده في **`src/shared/Config.luau`**. الوحش الجديد بيتضاف في `Config.Species`، وبعدين تحطه في `Weights` بتاعة أي بيضة.
