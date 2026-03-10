import Foundation

/// Maps exercise names to instructional video URLs (from Coach Alan Dyck's plan).
/// Used in Sonya's build to show a video link button next to each exercise.
enum ExerciseVideoLinks {
    static let urls: [String: String] = [
        // Workout #1 — Legs
        "Thigh Extensions (Regular)":   "https://youtu.be/FFzb3LwStEU",
        "Lying Leg Curls":              "https://youtu.be/2IagW5VRek8",
        "Walking DB Lunges":            "https://youtu.be/ciFJgEqy5mY",
        "Thigh Extensions (Toes Out)":  "https://youtu.be/xiq_KYYy-Dc",
        "Hack Squats":                  "https://youtu.be/qVz5aHeoqAw",
        "Leg Press Calf Raises":        "https://youtu.be/eA4DDlT7f6I",
        "Crunches":                     "https://youtu.be/CmS16eFGc34",
        "Leg Raises":                   "https://youtu.be/H1i0D3zdcBA",

        // Workout #2 — Chest/Shoulders/Triceps/Core
        "Seated Cable Chest Press":     "https://www.youtube.com/shorts/LNH_lPYJnpw",
        "Twists":                       "https://youtu.be/y4D56QKG3v0",
        "Straight Arm Lat Pulldown":    "https://www.youtube.com/shorts/lnec6DdscJU",
        "Side Crunches":                "https://youtu.be/FPxfzG-iV9w",
        "Cable Chest Fly":              "https://www.youtube.com/shorts/I-Ue34qLxc4",
        "DB Shoulder Press":            "https://youtu.be/0hUBvESF1UA",
        "Cable Upright Rows":           "https://youtu.be/HSjsbhP48lc",
        "Palms Up Pulldowns (Triceps)": "https://youtu.be/KB-KTdIWcrc",
        "Rear Delt Rope Face Pulls":    "https://youtu.be/GLgRulRAU-8",
        "Overhead Rope Tricep Extensions": "https://youtu.be/jG0sCOa3LI4",

        // Workout #3 — Back/Biceps/Ass
        "Pull-ups (Assisted)":          "https://youtu.be/4poStkLhRvY",
        "BB Bent Over Rows":            "https://youtu.be/UbjeLvfAT3s",
        "Side Cable Leg Raises":        "https://youtu.be/mBtGIOeBVr0",
        "Donkey Kicks (Cable)":         "https://youtu.be/zlBtVBbzVmI",
        "Seated Wide Bar Rows":         "https://youtu.be/n9ukpN-UiWY",
        "DB Curls":                     "https://youtu.be/dRrSpYOZGNc",
        "Rope Hammer Curls":            "https://youtu.be/4BKUPs_T85E",
        "Back Extensions (Glutes)":     "https://youtu.be/7qouPZK9xFs",

        // Workout #4 — Legs
        "Jump Squats":                  "https://youtu.be/RgrB6piOFTU",
        "Split DB Squats":              "https://youtu.be/usb8s_Us6dY",
        "Goblet Squats":                "https://youtu.be/HeoAkMev8mI",
        "Walking Lunges":               "https://youtu.be/YmSHlYNOb9w",
        "Hand to Toe Core Blasts":      "https://youtu.be/uCHt941p_Hs",
        "Seated Calf Raises":           "https://youtu.be/ejW7wsL7Ntc",

        // Workout #5 — Chest/Shoulders/Triceps/Core
        "Flat DB Bench Press":          "https://youtu.be/K0YstYJV420",
        "Bench Leg Raises":             "https://youtu.be/dASR1abJBw4",
        "Bench Dips":                   "https://youtu.be/MKy38XKTWw8",
        "Plank Hip Touches":            "https://youtu.be/f379OMAx7qQ",
        "Rope Face Pulls":              "https://youtu.be/GLgRulRAU-8",
        "Wide Cable Upright Rows":      "https://youtu.be/kGRWpPlCn7g",
        "Palms Down Tricep Press":      "https://youtu.be/IR8QlKVSGMs",
        "Bent Over Rear Delt DB Raises": "https://youtu.be/_NFmf_Y_O3s",
        "DB Skull Crushers":            "https://youtu.be/p3zXKsO3DYM",

        // Workout #6 — Back/Biceps/Ass
        "Wide Lat Pulldowns":           "https://youtu.be/V_FcbfdJFwU",
        "Banded Jump Squats":           "https://youtu.be/Bvcy28pDjfc",
        "Seated Close Rows":            "https://youtu.be/ROHUSZOpMAo",
        "Wide DB Curls":                "https://youtu.be/NDod84ohNvU",
    ]

    static func url(for exerciseName: String) -> URL? {
        guard let str = urls[exerciseName] else { return nil }
        return URL(string: str)
    }
}
