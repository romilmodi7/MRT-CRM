# MRT CRM - Flutter app (Mindripple Technologies)

HOW TO GET THE APK
1. Make sure the Laravel backend zip is uploaded first (see its README).
2. In your GitHub repo romilmodi7/Chat-App: delete the old Android/Java files (old WebView app: app/, gradle/, build.gradle, settings.gradle, gradle.properties, old .github/workflows files) so only this project remains.
3. Upload everything from this zip to the repo root (keep folders). Commit once.
4. GitHub > Actions > "Build MRT CRM APK" > open the run > download artifact "mrt-crm-apk" > install app-release.apk.
   New app id: com.mindrippletech.employee_chat (installs beside the old app; uninstall the old one later).

If the build fails, open the failed step, copy the red error lines and send them - fixes are quick.

FEATURES
- Splash with logo, one-time login (stays signed in), permissions asked on first launch
- Employee chat + groups: text, photos, files, unread, sound on/off
- PIN in the employee-chat search opens the private chat; Lock returns to employee chat
- Private chat locks after 10 min inactivity or when the app is closed
- Private chat: rooms, room-user login, voice notes, reactions, reply (swipe), edit, delete, pin, search, stickers, GIFs, location, images view-only (no save, no screenshots)
- Gallery backup, live location (while the app is open)
- Instagram / YouTube links open in their apps
- Light / Dark / Auto theme + chat backgrounds

NOT INCLUDED: push notifications when app is closed (needs Firebase), share-into-app from other apps, group creation.
