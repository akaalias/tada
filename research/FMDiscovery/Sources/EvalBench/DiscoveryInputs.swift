import Foundation

/// The curated set of ~30 diverse user one-liners that drive the eval loop.
/// Spans travel, health, admin, home, social, career, creative/ideation,
/// learning, shopping, finance. Reviewable / editable by the user.
public enum DiscoveryInputs {
    /// Fixed 10-case dev subset for fast/cheap iteration (full 30 confirms keepers).
    /// Spread across hard cases (tax, bakery, paris) and common ones.
    public static let devSubsetIDs: Set<String> = [
        "trip_paris", "gp_appointment", "tax_returns_de", "bakery_name", "wedding_plan",
        "resume_refresh", "buy_used_car", "dinner_party", "learn_guitar", "find_therapist",
    ]

    public static let all: [(id: String, input: String)] = [
        ("trip_paris",          "Plan a trip to Paris"),
        ("gp_appointment",      "Book a GP appointment"),
        ("tax_returns_de",      "Untangle my German tax returns for 2020-2024"),
        ("kitchen_reno",        "Renovate my kitchen"),
        ("dinner_party",        "Throw a dinner party for 8 friends"),
        ("job_interview",       "Prepare for a software engineering job interview"),
        ("apartment_move",      "Move to a new apartment across the city"),
        ("reading_habit",       "Build a daily reading habit"),
        ("balcony_redesign",    "Redesign my small balcony"),
        ("learn_guitar",        "Learn to play guitar"),
        ("resume_refresh",      "Update my resume for a product manager role"),
        ("wedding_speech",      "Write a best man speech"),
        ("side_business",       "Start a side business selling ceramics"),
        ("household_budget",    "Set up a monthly household budget"),
        ("running_comeback",    "Get back into running after an injury"),
        ("dad_birthday_gift",   "Find a birthday gift for my dad"),
        ("declutter_home",      "Declutter my entire apartment"),
        ("learn_spanish",       "Learn conversational Spanish before a trip"),
        ("buy_used_car",        "Buy a used car"),
        ("bakery_name",         "Brainstorm a name for my new bakery"),
        ("meal_prep",           "Start meal prepping for the week"),
        ("find_therapist",      "Find a therapist"),
        ("team_offsite",        "Organize a team offsite"),
        ("veggie_garden",       "Start a vegetable garden"),
        ("history_podcast",     "Start a podcast about local history"),
        ("retirement_savings",  "Figure out how to start saving for retirement"),
        ("adopt_dog",           "Adopt a dog"),
        ("portfolio_site",      "Build a portfolio website to showcase my design work"),
        ("quit_smoking",        "Quit smoking"),
        ("wedding_plan",        "Plan our wedding for next summer"),
    ]
}
