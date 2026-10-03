# 🔖 পরেরবার কী করব — Flutter Cheat Sheet

**Repo:** https://github.com/Keshab1997/flutter-bootstrap
**Raw setup (কপি করার সরাসরি লিংক):** https://raw.githubusercontent.com/Keshab1997/flutter-bootstrap/main/setup.sh
**কেন:** AI agent-এর sandbox-এ Flutter SDK থাকে না, আর একবার install করলেও পরের session-এ মুছে যায়। এই repo এক কমান্ডে ~৫৫ সেকেন্ডে Flutter বসিয়ে দেয়।

---

## ✅ সবচেয়ে সহজ উপায় (৯০% সময় এটাই)

যেকোনো AI agent-এর চ্যাটে গিয়ে **শুধু এই লাইনটা paste করুন**:

```
Clone https://github.com/Keshab1997/flutter-bootstrap and follow its README.md
to give yourself a Flutter SDK, then run flutter pub get, flutter analyze and
flutter test on <আপনার repo বা path> and report what you find.
```

বাংলায় লিখলেও চলবে:

```
https://github.com/Keshab1997/flutter-bootstrap clone করে README.md অনুযায়ী
তোমার sandbox-এ Flutter SDK বসাও। তারপর <repo/path> ক্লোন করে flutter pub get,
flutter analyze আর flutter test চালাও, ফলাফল আমাকে দেখাও।
```

### আপনার কাজ মাত্র ১টা ক্লিক

| ধাপ | কী করবেন | সময় |
|---|---|---|
| 1️⃣ | কিছুই না — কোনো browser approval নেই, কোনো code নেই, কোনো token নেই | ০ সেকেন্ড |

এটা `agent-bootstrap`-এর মতো নয়: **কোনো device code নেই**, কারণ এখানে কারও account-এ login করা লাগে না। শুধু Google-এর official Flutter storage থেকে SDK নামে।

---

## ⏱️ কত সময় লাগে (বাস্তবে মাপা)

| কাজ | সময় |
|---|---|
| Flutter download (1.5 GB) + extract + setup | **~৫৫ সেকেন্ড** |
| `flutter pub get` (৫০ প্যাকেজের app) | ~২৫ সেকেন্ড |
| `flutter analyze` | **২৪ সেকেন্ড** |
| `flutter test` (১৯০টা test) | **৬৪ সেকেন্ড** |

পুরো ব্যাপারটা ১ GB RAM, ২ core-এ পরীক্ষা করা — কাজ করে। `setup.sh` নিজেই ২ GB swap যোগ করে দেয়।

---

## 🔁 একই session-এ বার বার দরকার হলে

`setup.sh` নিজে থেকেই `flutter` আর `dart`-কে `/usr/local/bin`-এ symlink করে দেয়, তাই সাধারণ `flutter analyze` লিখলেই চলে। তাও না হলে:

```bash
export PATH=/opt/flutter/bin:$PATH
```

অথবা:

```bash
source env.sh        # PATH + PUB_CACHE + fb_check helper
fb_check /var/tmp/projects/my_app     # pub get + analyze + test একসাথে
```

**গুরুত্বপূর্ণ:** project গুলো `/var/tmp/projects/...`-এ clone করুন, `~`-তে না। `~`-র সব কিছু snapshot-এ যায়, তাই SDK/package cache ওখানে রাখলে snapshot ফুলে যায়।

---

## 🧰 হাতের কাছের কমান্ড

```bash
# install (idempotent — আগে থাকলে <1 সেকেন্ডে বেরিয়ে যায়)
bash <(curl -fsSL https://raw.githubusercontent.com/Keshab1997/flutter-bootstrap/main/setup.sh)

# একেবারে নিশ্চিত হতে: নিজে একটা app বানিয়ে analyze+test করে দেখায়
bash setup.sh --deep-verify

# নির্দিষ্ট version
bash setup.sh --version 3.46.0

# web build-এর জন্য engine artifacts আগেই নামিয়ে রাখতে
bash setup.sh --precache web

# শুধু ফলাফল (agent-friendly)
bash setup.sh --quiet --json
```

---

## 🩺 সমস্যা হলে

| সমস্যা | সমাধান |
|---|---|
| `flutter: command not found` | ওই shell-এ `export PATH=/opt/flutter/bin:$PATH` |
| `dubious ownership` | `git config --global --add safe.directory /opt/flutter` |
| `No pubspec.yaml file found` | project folder-এ ঢোকেননি |
| `pub get` মাঝপথে কেটে গেল / OOM | `free -m` দেখুন; swap আছে কিনা। দরকারে `sudo swapon /swapfile` |
| version মিলছে না | `flutter --version` আর `pubspec.yaml`-এর `sdk:` line মিলতে হবে → `--version` দিয়ে নতুন করে setup |
| `flutter doctor` Android/Xcode নিয়ে নালিশ করে | চিন্তা নেই — `analyze`, `test`, `build web`-এ Android SDK লাগে না |
| disk ভরে যাচ্ছে | `rm -rf /var/tmp/fb-dl /var/tmp/pub-cache` |

---

## 🔐 নিরাপত্তা

- এই repo-তে **কোনো secret, token বা password নেই** — কাউকে authorize করতে হয় না।
- একমাত্র download source: Google-এর official Flutter storage, আর সেটা **sha256 verify** করা হয় (মিল না হলে সাথে সাথে থেমে যায়)।
- Telemetry বন্ধ করা হয় installer-এ।
- `sudo` লাগে শুধু `/opt/flutter`, `/swapfile` আর `/usr/local/bin` symlink-এর জন্য।

---

## 🧠 মনে রাখার মতো তিনটা লাইন

1. **Flutter sandbox-এ রাখা যায় না** — ২.৫ GB, পরের session-এ যায়। তাই install on demand।
2. **প্রতি session-এ ~৫৫ সেকেন্ড** — এটাই আসল খরচ, আর এটা ঠিক আছে।
3. **একটা লাইন paste করলেই হয়** — উপরের prompt টা। কোনো approval লাগে না।
