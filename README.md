# WorkoutTracker

A full-featured iOS + Apple Watch workout tracker built with SwiftUI, Supabase, and Claude AI.

Track your lifts, monitor progression, get AI-powered analysis after every session, and stay on top of your training — all from your wrist or pocket.

---

## Features

### Workout Tracking
- **Active workout UI** with real-time elapsed timer, set logging, and weight/reps input
- **Progression engine** — automatic suggestions to increase weight or reps based on your history
- **Superset support** with interleaved set display and smart rest handling
- **Rest timer** with customizable durations, floating countdown bar, and haptic/audio cues
- **150+ exercise database** with muscle groups and equipment tags
- **Offline-first** — works without internet, syncs when connected

### AI-Powered Coaching (Claude)
- **Post-workout analysis** — detailed breakdown of your session: volume changes, plateau alerts, per-exercise suggestions (increase weight, add reps, try drop sets)
- **Pre-workout session goals** — AI-generated targets based on your recent performance
- **Pattern recognition** — understands descending rep schemes, fatigue, and drop sets
- **Cached results** stored in Supabase to avoid redundant API calls

### Apple Watch App
- Standalone companion app with live workout view
- Real-time heart rate display, rest countdown, and exercise tracking
- Always-on display support with optimized layout
- Skip rest timer from your wrist
- Home screen widgets (circular, rectangular, corner, inline)

### Analytics & Progress
- **Personal Records** — searchable PR list with muscle group filters
- **Exercise progress charts** — E1RM trends over time
- **Overload tracker** — identifies progressing, stalling, and regressing exercises
- **Muscle balance scoring** — compare actual vs target volume per muscle group
- **Weekly reports** — volume trends, duration analytics, muscle recovery tracking
- **Body composition** — weight trends with period comparisons (30/60/90 days)

### Progress Photography
- Three-pose capture system (front, side, back) with timer camera
- Photo comparison view for side-by-side progress tracking
- Weight associated with each photo session

### Health Integration
- **HealthKit sync** — imports body weight, heart rate, and Apple Health workouts
- **Live heart rate** during workouts via Apple Watch
- **Calories and avg HR** stored per session

### Home Screen Widgets
- Today's routine with workout icon
- Next routine preview
- Rest day indicator
- Available for iPhone and Apple Watch

### Routine Management
- Create, edit, and reorder routines with full exercise configuration
- Set target sets, rep ranges, rest periods, superset groups, and notes
- Editable weekly schedule synced across devices
- Deload week tracking with auto-suggestions every 3rd week

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| iOS App | SwiftUI, Swift 6, Xcode 16+ |
| Watch App | WatchKit, WatchConnectivity |
| Backend | [Supabase](https://supabase.com) (PostgreSQL + REST API) |
| AI | [Claude API](https://docs.anthropic.com) (Anthropic) |
| Health | HealthKit (heart rate, body weight, workouts) |
| Sync | Offline queue with auto-retry, local caching |

---

## Getting Started

### Prerequisites
- Xcode 16+ with iOS 18 / watchOS 11 SDK
- A free [Supabase](https://supabase.com) account
- An [Anthropic API key](https://console.anthropic.com) (optional — for AI features)

### 1. Clone the repo
```bash
git clone https://github.com/hbliznakov21/WorkoutTracker-Public.git
cd WorkoutTracker-Public
```

### 2. Set up Supabase
1. Create a new project at [supabase.com](https://supabase.com)
2. Go to **SQL Editor** and paste the contents of [`supabase-setup.sql`](supabase-setup.sql)
3. Click **Run** to create all tables
4. (Optional) Uncomment the seed data section at the bottom to populate starter exercises

### 3. Configure the app
```bash
cp WorkoutTracker/Config.plist.example WorkoutTracker/Config.plist
```
Edit `Config.plist` and fill in:
- `SUPABASE_URL` — your project's REST URL (e.g., `https://abc123.supabase.co/rest/v1`)
- `SUPABASE_ANON_KEY` — found in Supabase Dashboard > Settings > API
- `ANTHROPIC_API_KEY` — from [console.anthropic.com](https://console.anthropic.com) (leave empty to skip AI features)

### 4. Open in Xcode
```bash
open WorkoutTracker.xcodeproj
```
Select the **WorkoutTracker** scheme, pick your device or simulator, and run.

---

## Project Structure

```
WorkoutTracker/
├── WorkoutTracker/              # iOS app source
│   ├── Models.swift             # All data models (Codable structs)
│   ├── WorkoutStore.swift       # Main state store (@Observable)
│   ├── WorkoutStore+AI.swift    # Claude AI integration
│   ├── WorkoutStore+Analytics.swift
│   ├── WorkoutStore+Schedule.swift
│   ├── SupabaseClient.swift     # REST API client (no SDK needed)
│   ├── ClaudeClient.swift       # Anthropic API client
│   ├── OfflineQueue.swift       # Offline sync queue
│   ├── HomeView.swift           # Home screen
│   ├── ActiveWorkoutView.swift  # Active workout UI
│   ├── ExerciseBlock.swift      # Set logging components
│   └── ...
├── WorkoutTracker Watch App/    # Apple Watch companion
├── iOSWidgetExtension/          # iPhone home screen widget
├── WorkoutWidgetExtension/      # Watch complications
├── supabase-setup.sql           # Database schema
└── Config.plist.example         # Template for API keys
```

---

## Architecture

- **@Observable pattern** — reactive state management on MainActor
- **Offline-first** — all writes queue locally and sync when network returns (up to 5 retries)
- **No Supabase SDK** — lightweight REST via `URLSession` for full control
- **AI as a layer** — Claude integration is optional; app works fully without it
- **WatchConnectivity** — bidirectional sync between phone and watch (rest timer, workout state, exercise data)

---

## Built With AI

This entire app was built using [Claude Code](https://claude.ai/claude-code) (Anthropic's CLI for Claude). From architecture decisions to UI polish, every line was written in collaboration with AI — proof that a solo developer can ship a production-grade, multi-platform app with the right tools.

---

## Screenshots

*Coming soon — contributions welcome!*

---

## Contributing

Contributions are welcome! Feel free to:
- Open issues for bugs or feature requests
- Submit PRs for improvements
- Share your workout routines and exercise databases

---

## License

MIT License — see [LICENSE](LICENSE) for details.

---

**Built by [Hristo Bliznakov](https://github.com/hbliznakov21)** — a 50-year-old lifter from Belgium who wanted the perfect workout tracker and decided to build it himself.
