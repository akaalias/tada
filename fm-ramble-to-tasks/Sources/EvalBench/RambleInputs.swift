import Foundation

/// The input set the harness evaluates over. `kind` documents what the case
/// stresses; `heldOutReal` marks real dogfooded rambles (frozen test, gold
/// human-verified) vs. synthetic seeds. Gold itself is produced by GoldGenerator
/// (Sonnet) and frozen in `gold/`.
public struct RambleInput: Sendable {
    public let id: String
    public let kind: String        // zero | single | multi | interleaved | bait | noisy | mixed | dedup | long
    public let heldOutReal: Bool
    public let input: String
}

public enum RambleInputs {
    public static let all: [RambleInput] = [
        // ── Real held-out (dogfooded) — gold human-verified ──
        RambleInput(id: "real_franziska", kind: "multi", heldOutReal: true,
            input: "Okay so yeah let me think. I want to review the 2024 tax document with Franziska. I got to talk to her about August. And I should probably bring out the trash."),

        // ── Clean archetypes ──
        RambleInput(id: "single_paris", kind: "single", heldOutReal: false,
            input: "I really need to finally book the flights for the Paris trip sometime this week."),
        RambleInput(id: "multi_errands", kind: "multi", heldOutReal: false,
            input: "Let me think — I need to call the dentist to reschedule, we're out of coffee so grab some, and I should finally start the quarterly report."),
        RambleInput(id: "interleaved_deck", kind: "interleaved", heldOutReal: false,
            input: "I should email Sarah the deck... oh and I need to book the offsite venue... actually for that deck, make sure the Q3 numbers are in before it goes to Sarah."),

        // ── Zero / bait (the #1 failure mode: don't invent tasks) ──
        RambleInput(id: "zero_venting", kind: "zero", heldOutReal: false,
            input: "Ugh today just dragged on forever, the traffic this morning was insane and I'm completely wiped out. Anyway."),
        RambleInput(id: "zero_chitchat", kind: "zero", heldOutReal: false,
            input: "Man, the weather has been wild lately, gray and rainy basically all week. My back is a bit stiff from sitting too much. Just thinking out loud here, nothing major going on really."),
        RambleInput(id: "bait_journal", kind: "bait", heldOutReal: false,
            input: "I've been thinking it would be nice to be the kind of person who journals more, you know, more reflective."),
        RambleInput(id: "bait_someday", kind: "bait", heldOutReal: false,
            input: "I keep daydreaming about maybe learning the piano one day, and being someone who reads way more novels. Would just be nice to feel a bit more cultured, you know?"),

        // ── Noisy dictation: self-correction, retraction, filler ──
        RambleInput(id: "noisy_selfcorrect", kind: "noisy", heldOutReal: false,
            input: "Okay so I need to call the, um, no wait, I should just email the landlord about the leaking faucet, yeah email is better because I want it in writing."),

        // ── Mixed: one real task buried in non-actionable rambling ──
        RambleInput(id: "mixed_weekend", kind: "mixed", heldOutReal: false,
            input: "This weekend was pretty chill honestly, watched a couple of movies, slept in way too late. Oh, but I do need to return that Amazon package before the window closes on Tuesday. Other than that, just relaxing really."),

        // ── Dedup: the same intention said twice in different words ──
        RambleInput(id: "dedup_groceries", kind: "dedup", heldOutReal: false,
            input: "We're basically out of milk so I need to grab some on the way home, and actually, you know what, definitely pick up milk, we finished the last carton this morning."),

        // ── High count: many distinct tasks ──
        RambleInput(id: "multi_moving", kind: "multi", heldOutReal: false,
            input: "Okay the move is coming up fast. I need to book the moving truck, set up mail forwarding with the post office, cancel my gym membership here, give notice to the landlord, and I really should start packing the kitchen this weekend."),

        // ── Ambiguous boundary: one task as stated (don't over-decompose) ──
        RambleInput(id: "boundary_dinner", kind: "single", heldOutReal: false,
            input: "I want to host a dinner party for my parents' anniversary sometime next month."),

        // ── Long (~2 min): tasks scattered through tangents, a returned-to thread, and a someday non-task ──
        RambleInput(id: "long_monday", kind: "long", heldOutReal: false,
            input: "Okay let me just think out loud for a sec because my head is all over the place this morning. So the big thing is the Henderson proposal, I really need to finish the draft and get it over to Mark by Thursday, he keeps asking about it. Ugh and the coffee machine at the office is broken again, so annoying. Anyway, I also told Lisa I would send her the updated budget spreadsheet, that's been sitting in my drafts for like a week now. Oh and at some point I need to book a dentist appointment, my tooth has been bugging me. The weather is supposed to be nice this weekend which would be great. Let me see, what else, I should probably call the insurance company about that claim, they never got back to me. And actually back to the Henderson thing, before I send it to Mark I need to double check the numbers in section three, I think there's a typo in there. I keep meaning to clean out the garage too but honestly that's more of a someday thing, not urgent at all. Oh, and I need to renew my passport, it expires in a couple months and we might travel. I think that's most of it. My brain feels a little less cluttered now."),

        // ── Long (~1.5 min): trip planning with a retraction and tangents ──
        RambleInput(id: "long_portugal", kind: "long", heldOutReal: false,
            input: "So we're finally doing the Portugal trip in the fall and there's a bunch to sort out. First I need to book the flights, prices keep creeping up so the sooner the better. We also need to find a place to stay, probably an Airbnb in Lisbon for the first few nights. I'm so excited honestly, been wanting to go for years. Let me think, I need to renew my, oh wait no, my passport is actually fine, scratch that. I should make a list of the towns we want to visit, and I need to ask my neighbor if she can water the plants while we're away. Oh and I have to set an out of office for work before we leave. The food there is supposed to be incredible. I think that's the main stuff for now."),

        // ── Fresh held-out zero/bait, deliberately UNLIKE any prompt example, to
        //    honestly test whether a zero-task fix generalizes (not memorizes) ──
        RambleInput(id: "zero_frustrated", kind: "zero", heldOutReal: false,
            input: "Honestly I'm just so frustrated with my coworker right now, he never replies to anything and it's driving me up the wall. Needed to get that off my chest."),
        RambleInput(id: "bait_ocean", kind: "bait", heldOutReal: false,
            input: "Wouldn't it be cool to live by the ocean someday and just surf every morning before work? A person can dream I guess."),

        // ── More coverage (dev) ──
        RambleInput(id: "single_plumber", kind: "single", heldOutReal: false,
            input: "I really have to call a plumber about the kitchen sink, it has been dripping for days now."),
        RambleInput(id: "multi_morning", kind: "multi", heldOutReal: false,
            input: "This morning I need to drop the kids at school, pick up my dry cleaning, and swing by the pharmacy for my prescription."),
        RambleInput(id: "interleaved_party", kind: "interleaved", heldOutReal: false,
            input: "I should invite Tom to the barbecue this weekend, oh and I need to buy charcoal, and actually for the barbecue I have to text Tom the address too."),
        RambleInput(id: "mixed_gym", kind: "mixed", heldOutReal: false,
            input: "Felt great after the gym today, honestly I need to keep that up. Anyway, I have to renew my car registration before it expires on Friday."),
        RambleInput(id: "dedup_email", kind: "dedup", heldOutReal: false,
            input: "I need to reply to Dana's email about the contract. Yeah, definitely have to get back to Dana on that contract thing today."),
        RambleInput(id: "noisy_filler", kind: "noisy", heldOutReal: false,
            input: "So um, I guess I should, like, finally schedule the annual eye exam, my prescription is pretty old at this point."),

        // ── More held-out (test) ──
        RambleInput(id: "zero_reflect", kind: "zero", heldOutReal: false,
            input: "I keep thinking about how fast this year has gone by. Feels like just yesterday it was spring. Time is strange, huh."),
        RambleInput(id: "long_household", kind: "long", heldOutReal: false,
            input: "Okay, household stuff, let me get it out of my head. The dishwasher has been making that weird noise again so I need to book a repair. The kids' school sent a form I have to fill out and send back by Wednesday. The houseplants are looking sad, I should water them, although honestly that is kind of a daily thing not really a task. I keep meaning to finally sort through the garage but that is a someday project, not now. We are low on dog food so I need to order more. And I promised my sister I would send her those photos from the trip, I really have to do that. The living room could use a fresh coat of paint one day, would be nice. Let me also remember to pay the electricity bill, it is due at the end of the month. I think that covers the main things rattling around up there."),
    ]

    /// Held-out TEST split — the honest gate. The autoresearch agent never optimizes
    /// or crafts examples toward these. Includes fresh zero/bait cases unlike any
    /// prompt example, plus the real dogfooded case. The loop gates on DEV (the rest).
    public static let testIDs: Set<String> = [
        "real_franziska", "bait_journal", "bait_someday",
        "zero_frustrated", "bait_ocean", "long_portugal",
        "zero_reflect", "long_household",
    ]
    public static func isTest(_ id: String) -> Bool { testIDs.contains(id) }

    public static func named(_ id: String) -> RambleInput? { all.first { $0.id == id } }
}
