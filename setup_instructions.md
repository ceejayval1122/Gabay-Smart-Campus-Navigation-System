# Email Confirmation Fix - Setup Instructions

## Problem Fixed
Your Supabase email confirmation was redirecting to `http://localhost:3000` but no server was running there, causing "site cannot be reached" errors.

## Solution Implemented
1. **Auth Server**: Created a Python HTTP server that runs on `http://localhost:3001`
2. **Redirect Handler**: Added a web page that handles the auth callback and redirects back to your app
3. **Deep Linking**: Configured Android and iOS to handle deep links from the web page

## What You Need to Do

### 1. Update Supabase Dashboard
Go to your Supabase project dashboard:
1. Navigate to **Authentication** → **Settings**
2. Find the **Site URL** section
3. Add this redirect URL: `http://localhost:3001`
4. Click **Save**

### 2. Run the Auth Server
Before testing email confirmation:
```bash
python start_auth_server.py
```
The server will start on `http://localhost:3001`

### 3. Test Email Confirmation
1. Run your Flutter app
2. Try to sign up with a new email
3. Check your email and click the confirmation link
4. You should be redirected to the auth server page
5. The page will automatically redirect back to your app

## How It Works
1. User clicks email confirmation link
2. Supabase redirects to `http://localhost:3001` with auth tokens
3. Python server serves the callback page
4. JavaScript extracts tokens and redirects to your app via deep link
5. Your app receives the tokens and completes the authentication

## Files Created/Modified
- `start_auth_server.py` - Python HTTP server for auth callbacks
- `web/auth-callback.html` - Web page that handles redirects
- `.env` - Added `SUPABASE_REDIRECT_URL=http://localhost:3001`
- `lib/main.dart` - Updated Supabase initialization with redirect URL
- `lib/repositories/auth_repository.dart` - Updated sign up with redirect URL
- `android/app/src/main/AndroidManifest.xml` - Added deep link support
- `ios/Runner/Info.plist` - Added URL scheme support

## Troubleshooting
- If port 3001 is in use, change the port in `start_auth_server.py` and `.env`
- Make sure the auth server is running before testing email confirmation
- Check browser console for any JavaScript errors on the callback page

## Production Deployment
For production, you'll need to:
1. Deploy the auth server to a real domain (e.g., `https://yourapp.com/auth-callback`)
2. Update the redirect URL in Supabase dashboard
3. Update the deep link scheme to match your app's production URL scheme
