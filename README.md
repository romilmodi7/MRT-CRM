# MRT CRM - Flutter app (Mindripple Technologies)

HOW TO GET THE APK
1. Upload everything from this zip to the root of a GitHub repo (keep folders). The hidden folder `.github/workflows/build-apk.yml`
   must be there: if the web upload skips it, use "Add file > Create new file" and name it `.github/workflows/build-apk.yml`.
2. GitHub > Actions > "Build MRT CRM APK" > open the run (about 8 min) > download artifact "mrt-crm-apk" > unzip > install app-release.apk.
   Uninstall any older version of the app first.
3. Laravel backend: upload laravel-backend-FINAL.zip files (see its README.txt), then `php artisan optimize:clear` and `php artisan cache:clear`.

WHAT IS IN THE APP
- App name MRT CRM, logo icon (assets/logo_icon.png, built into all launcher sizes), dark-blue launch screen + animated splash (no white flash)
- Employee chat + groups: text, photos, files, stickers, unread, sound on/off, full-screen photo viewer (zoom, swipe down to close)
- Private chat (PIN typed in the Chats search box): rooms, text/photo/video/voice/file/location/contact/GIF/stickers, reply, edit, react, search,
  gallery backup (asks once, then automatic; switch to turn off), live location
- Private chat locks at once when the app goes to the background, the phone locks or the app is closed (and after 10 min idle)
- Appearance: Light / Dark / Auto, 9 colour themes, own colour for sent and received bubbles, reset
- Sticker packs: Work, Happy, Mood, Festival, Reactions
- Auto login (one login only), permissions asked on first launch, crash guards (no red error screen)
