# Stom backend

A minimal Node.js/Express server with two endpoints. Every installation of
the app is identified by an anonymous **device id** (a random id generated
on first launch, no login/registration). All of that device's data --
patients, tooth notes, x-ray images -- is stored as one flexible JSON
document in MongoDB, keyed by that device id.

- `GET /api/user/:deviceId` -- returns everything stored for that device.
- `PUT /api/user/:deviceId` -- replaces everything stored for that device
  with the JSON body `{ "data": { ...whatever the app sends... } }`.

That's it. No other endpoints, no auth, on purpose -- this is meant to be
the simplest thing that works, not a finished product. See the "known
limitations" section at the bottom before you rely on this for real patient
data.

---

## 1. Create a free MongoDB Atlas cluster

You said you already have an Atlas account but no cluster yet, so:

1. Go to https://cloud.mongodb.com and log in.
2. Click **"Build a Database"** (or **"+ Create"** if you're inside an
   existing project).
3. Pick the **M0 Free** tier. Choose any cloud provider/region close to
   you. Name the cluster (e.g. `stom-cluster`). Click **Create**.
4. You'll land on a "Security Quickstart" step:
   - **Create a database user**: pick a username and a strong password.
     Write the password down -- you'll need it in a moment. (If it
     contains `@`, `:`, `/`, or other special characters, you'll need to
     URL-encode them in the connection string later -- simplest is to
     just avoid special characters in the password.)
   - **Network Access**: click **"Add My Current IP Address"** for now so
     you can test locally. You'll add a wider rule later when you deploy.
5. Wait for the cluster to finish deploying (a minute or two).
6. Click **"Connect"** on your cluster -> **"Drivers"** -> select
   **Node.js**. Copy the connection string. It looks like:
   ```
   mongodb+srv://<username>:<password>@stom-cluster.xxxxx.mongodb.net/?retryWrites=true&w=majority
   ```
7. Replace `<username>` and `<password>` with your real database user
   credentials, and add a database name right after the hostname, e.g.:
   ```
   mongodb+srv://myuser:mypassword@stom-cluster.xxxxx.mongodb.net/stom?retryWrites=true&w=majority
   ```
   (The database itself, `stom`, doesn't need to exist beforehand -- Mongo
   creates it the first time data is written.)

---

## 2. Run it locally and test it

```bash
cd backend
npm install
copy .env.example .env        # (macOS/Linux: cp .env.example .env)
```

Open `.env` and paste your real connection string as `MONGODB_URI`.

```bash
npm start
```

You should see:
```
Connected to MongoDB
Stom backend listening on port 3000
```

Test it (in another terminal):

```bash
# Save some data for a fake device
curl -X PUT http://localhost:3000/api/user/test-device-1 ^
  -H "Content-Type: application/json" ^
  -d "{\"data\": {\"hello\": \"world\"}}"

# Read it back
curl http://localhost:3000/api/user/test-device-1
```

(Windows `curl` in PowerShell/cmd needs `^` for line continuation and
escaped quotes as shown above; on macOS/Linux/git-bash use `\` and single
quotes instead.)

If that round-trips correctly, the backend and database are wired up
correctly.

---

## 3. Deploy it so any phone running the APK can reach it

A server running on your laptop only answers requests from your laptop's
network. For the app to work after you build an APK and install it on a
different phone, the backend needs a real public URL. The free tier on
**Render** is the easiest way to get one:
,
1. Push this project to a GitHub repository (the whole repo is fine --
   Render can be pointed at the `backend` subfolder).
2. Go to https://render.com, sign up/log in.
3. Click **"New +"** -> **"Web Service"**.
4. Connect your GitHub repo. When configuring the service:
   - **Root Directory**: `backend`
   - **Build Command**: `npm install`
   - **Start Command**: `npm start`
   - **Instance Type**: Free
5. Under **Environment**, add an environment variable:
   - `MONGODB_URI` = the same connection string from step 1 above.
   - (You don't need to set `PORT` -- Render sets it automatically and
     the server already reads `process.env.PORT`.)
6. Back in MongoDB Atlas -> **Network Access**, add a rule for
   `0.0.0.0/0` ("Allow access from anywhere"). Render's free tier doesn't
   use a fixed outbound IP, so this is the simplest option for now. (This
   only controls which IPs can reach your database -- your database user
   password is still required, so this isn't the same as making the data
   itself public.)
7. Click **Deploy**. Render will give you a public URL like:
   ```
   https://stom-backend.onrender.com
   ```
8. Give me that URL and I'll wire it into the Flutter app (or update the
   `kBackendBaseUrl` constant in `lib/data/backend_sync_service.dart`
   yourself).

Note: Render's free tier "spins down" the server after ~15 minutes of no
traffic, so the *first* request after a quiet period can take 30-60
seconds while it wakes back up. Fine for testing; if that delay becomes
annoying in real use, upgrading to a paid Render instance (or any
always-on host) removes it.

---

## Known limitations (this is "very simple, for now" on purpose)

- **No authentication on the endpoints.** Anyone who knows (or guesses) a
  device id can read or overwrite that device's data. Fine for early
  testing; add an API key or real auth before this ever holds real
  patient data outside your own testing.
- **No login means no real "restore my data on a new phone."** The device
  id lives only in that install's local storage. Uninstalling the app (or
  installing on a second phone) creates a *new* device id with no
  connection to the old one's cloud data. This backend is a per-device
  backup, not an account system, until real login is added.
- **Images are embedded as base64 inside the same MongoDB document as
  everything else for that device.** Simple, but MongoDB caps a single
  document at 16 MB. A device with many x-rays could eventually hit that
  limit -- if/when that happens, images should move to their own
  collection (or GridFS/S3) instead of living inside the user document.
