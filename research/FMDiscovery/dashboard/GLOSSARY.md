# Glossary

Plain-English definitions and a concrete example for every ML/RL term used across `index.html`, `onboarding.html`, and `report.html`. Written for a non-technical reader.

---

## Models & scale

**Foundation Model (Apple's "FM")**
The general-purpose AI model that Apple builds directly into macOS. This project's whole goal is to use it instead of a model running in the cloud.
*Example:* Just as your Mac ships with a built-in dictionary and calculator, newer Macs ship with a built-in AI — that's the Foundation Model this project is testing.

**On-device**
Running the AI directly on your own computer, so nothing is sent over the internet to a company's servers.
*Example:* Face ID recognizes you entirely on your iPhone without uploading your face anywhere — that's on-device. The opposite is asking a chatbot online, where your words travel to a data center.

**Frontier model**
One of the largest, most capable AI models that currently exists — the top of the line. In this project, that's Claude Sonnet running in the cloud.
*Example:* If AI models were cars, a frontier model is the brand-new flagship; the on-device model is a compact economy car. Both drive — the question is how close the compact gets on this one route.

**Parameters / "3B" / ~3-billion-parameter**
Parameters are the adjustable internal numbers a model learns during training; roughly, more parameters means more capability. "3B" means about 3 billion of them — small by today's standards.
*Example:* Think of parameters as the knobs on an enormous mixing board. The on-device model has ~3 billion knobs; the cloud model has perhaps 20 times more, which is why it can do more.

**Base model / "the base"**
The original model you start from, before you've customized it for your specific task.
*Example:* The base model is flour, eggs, and sugar straight from the store — the raw starting point before you've baked anything specific with it.

**Stock model**
The model exactly as it ships, with no modifications — the untouched starting point.
*Example:* A "stock" car is the car as it left the factory, before anyone added custom parts. The stock model scored 0.28 before any of our changes.

**Capability vs. capacity ("capacity-bound")**
How much a model is fundamentally able to do — set mostly by its size — as opposed to how cleverly you ask it. "Capacity-bound" means the limit is the model's raw ability, not your technique.
*Example:* A toddler who can't reach a high shelf is height-bound; no amount of better instructions ("reach higher!") fixes it — they need to grow. The report concludes the small model is similarly capacity-bound.

**Teacher**
A stronger model whose answers are used to train a weaker one.
*Example:* Sonnet is the teacher here: it writes the "correct" answers, and the small on-device model tries to learn from them — like a student studying a star pupil's worked solutions.

---

## Core mechanics

**Inference / inference-time**
Running an already-trained model to get an answer (as opposed to training it). "Inference-time" changes are things you adjust when asking, without retraining.
*Example:* Inference is using a calculator; training is building the calculator. "Inference-time tricks" means getting better answers just by how you press the buttons, not by rewiring the device.

**Weights**
The millions of internal numbers that store everything a model has learned. Changing them *is* training the model.
*Example:* Weights are like the strength of every connection in a brain. "Baking the skill into the weights" means the model actually learned the skill, rather than being reminded of it each time you ask.

**Decoding**
How the model turns its internal hunches into the actual words it writes out.
*Example:* At each word the model has a ranked list of options ("Paris" 60%, "France" 20%, …). Decoding is the rule for choosing from that list.

**Greedy (decoding)**
A decoding rule that always picks the single most likely next word. Predictable, with no randomness.
*Example:* Greedy is autocomplete that always takes its top suggestion. Ask the same thing twice, you get the identical answer every time.

**Sampling (decoding)**
A decoding rule that adds randomness, so the same question can produce different answers each time.
*Example:* Sampling is rolling weighted dice instead of always taking the favorite. It adds variety — but the project found it also added noise that faked progress.

**Temperature**
A dial for how much randomness sampling uses. Higher means more varied and surprising; lower means more predictable.
*Example:* Low temperature is a cautious writer who always picks the safe word; high temperature is a brainstormer who throws out wild options.

**Single shot**
Getting the answer in one model call, with no extra steps, retries, or follow-ups.
*Example:* Single shot is asking one question and taking the first reply — versus asking, critiquing, and re-asking several times.

**Baseline**
The starting score you compare every later improvement against.
*Example:* The baseline here is 0.28 — the stock model's score. Every experiment is judged by whether it beats that.

**Distribution ("the model's own distribution")**
The full range of answers a model would naturally produce, in its own characteristic style.
*Example:* Each writer has a natural voice. Pulling an extra question "from the model's own distribution" means generating it in the model's own voice, rather than pasting one in from somewhere else that would sound out of place.

**Natural-language manifold**
The space of text that reads like real, fluent human language. Training a model too aggressively can push it "off" this space into gibberish.
*Example:* Picture all sensible English as solid ground and nonsense as the cliff edge. Some training methods walk the model toward the edge; a "leash" (see *KL anchor*) keeps it on solid ground.

**Deterministic**
Always giving the exact same output for the same input — no randomness involved.
*Example:* A vending machine is deterministic: press B4, always get the same snack. The project made its scoring deterministic so results were trustworthy and repeatable.

---

## Training & fine-tuning

**Fine-tuning**
Taking an existing model and training it further on examples of one specific task, to make it better at that task.
*Example:* A general doctor doing a residency in cardiology is being fine-tuned — already broadly trained, now specialized.

**Adapter**
A small trained add-on that adjusts a model's behavior without rebuilding the whole model.
*Example:* An adapter is like a pair of prescription glasses for the model: a small, cheap attachment that changes what it does, without replacing its eyes.

**Low-Rank Adaptation (LoRA) adapter**
A popular, efficient kind of adapter — a lightweight patch to a model's weights that's far cheaper to train than retraining the whole model.
*Example:* Instead of repainting an entire house (retraining the whole model), LoRA is a few well-placed touch-ups that change the look for a fraction of the effort. Every score above 0.32 in this project runs on one.

**Supervised Fine-Tuning (SFT)**
Training by showing the model good example answers and effectively saying "produce answers like these."
*Example:* Teaching someone to write thank-you notes by handing them fifty great thank-you notes to emulate. They learn the style and format well — but only what's shown.

**Imitation**
Learning by copying good examples — the core idea behind SFT.
*Example:* A new cook who reproduces a chef's dishes exactly is imitating. They nail the recipe but haven't learned *why* those ingredients were chosen.

**Preference learning**
Training on *pairs* of answers — a better one and a worse one — so the model learns which is preferred, rather than just copying one "right" answer.
*Example:* Instead of only showing good essays, you show pairs ("this one is better than that one") so the learner picks up judgment about what makes one stronger.

**Preference pairs / chosen–rejected**
The good-answer / worse-answer couples used in preference learning. The "chosen" one is preferred; the "rejected" one isn't.
*Example:* For the same trip-to-Paris task: chosen = the question set that asks about budget; rejected = the one that forgot to. The model learns to lean toward the chosen kind.

**Odds Ratio Preference Optimization (ORPO)**
One specific recipe for preference learning — the name doesn't matter much; it's a method that learns from chosen-vs-rejected pairs.
*Example:* If preference learning is "teach by comparison," ORPO is one particular lesson plan for doing that.

**Reinforcement Learning (RL)**
Training by trial and reward: the model tries answers, gets a score, and is nudged toward whatever scores higher.
*Example:* Training a dog with treats — good behavior gets a reward, so it happens more. The model's "treat" is a high score from the judge.

**Group Relative Policy Optimization (GRPO)**
A reinforcement-learning recipe where the model generates a batch of its own answers, and the better ones in the batch are rewarded relative to the worse ones.
*Example:* Have the model write five answers, rank them against each other, and say "be more like the top ones, less like the bottom ones."

**Group-relative advantages**
GRPO's way of scoring each answer by how much better or worse it is than the *others in its own batch*, rather than against an absolute target.
*Example:* Grading a test on a curve within one classroom — your score depends on how you did versus your classmates, not a fixed cutoff.

**Reward / reward signal**
The score an RL model is trying to maximize.
*Example:* Points in a video game. The model "plays" to rack up as many as possible — here, points come from the judge.

**Judge-reward**
Using the automated judge's score directly as the reward the model trains toward.
*Example:* Instead of a human handing out points, the AI judge does — the model trains to make the judge happy.

**Policy gradient**
The underlying math of this style of RL: it figures out which direction to nudge the model's weights so that higher-reward answers become more likely.
*Example:* Like adjusting a recipe based on taste feedback — a little more salt got a better reaction, so shift that way. Policy gradient is the formal version of "nudge toward what worked."

**Kullback–Leibler anchor (KL anchor / KL-anchored)**
A leash that keeps a model being trained from drifting too far from its original, sensible behavior.
*Example:* Letting a kite fly higher but keeping it on a string so it doesn't blow away. Without the anchor, RL pushed the model into nonsense; the anchor pulled it back to normal language.

**Regularised / unregularised**
Whether such a restraint is applied. "Unregularised" means no leash — the model is free to drift; "regularised" means a constraint keeps it in check.
*Example:* Unregularised training is a teenager with no curfew; regularised is one with a curfew. The first one wandered off (into gibberish); the curfew fixed it.

**On-policy**
Training examples drawn from the model's *own current* answers, rather than from an outside source.
*Example:* A student studying critiques of *their own* essays (on-policy) versus studying critiques of a stranger's essays (off-policy). The first is more directly relevant to fixing their habits.

**Off-policy**
Training on examples from some other source rather than the model's own output.
*Example:* Learning to drive only by watching videos of *other* people driving — useful, but not tailored to your specific mistakes.

**Distillation**
Transferring ability from a big, capable model into a smaller one.
*Example:* A master chef writing a simplified cookbook so a home cook can approximate the restaurant dishes. The skill is "distilled" down to something the smaller cook can use.

**Generative Adversarial Distillation (GAD)**
A distillation method that pits two networks against each other: one tries to tell the small model's answers apart from the teacher's, which pressures the small model to make its answers indistinguishable.
*Example:* An art student (small model) tries to forge a master's paintings while a detective (the discriminator) tries to spot the fakes. The student improves by trying to fool the detective.

**Discriminator**
The network whose only job is to tell two kinds of answers apart — here, the teacher's real answers versus the small model's.
*Example:* The "detective" in the forgery analogy above. In this project, a probe showed it could spot the small model mostly by *style*, not by the substance we cared about.

**Critic**
A model trained to *judge or score* answers rather than to produce them.
*Example:* A film critic doesn't make movies; they rate them. The project tried training a critic to recognize good question sets — and even that couldn't reliably spot the most important question on new tasks.

---

## Prompting & inference techniques

**Prompt / prompting**
The exact wording of the request you give a model. "Prompting" means trying to get better results by rewording alone, without retraining.
*Example:* The difference between "write about dogs" and "write a 200-word vet's guide to puppy nutrition" is prompting. Same model, very different output.

**Prompting ceiling**
The best score you can reach by wording tricks alone, before you're forced to actually retrain the model.
*Example:* No matter how you phrase the request, the model topped out around 0.32 — that was the prompting ceiling. Breaking past it required fine-tuning.

**In-context**
Improvements made purely through the prompt and any examples you include in it — with no retraining.
*Example:* Slipping a few solved examples into your question so the model copies the pattern is an in-context trick. Nothing about the model changes; you've just given it better context for that one request.

**Retrieval-Augmented Generation (RAG)**
Fetching relevant material on the fly and adding it to the prompt so the model can lean on it.
*Example:* Before answering "plan a trip to Paris," the system digs up a few past trip-planning examples and pastes them in for reference — like grabbing relevant files before writing a report.

**Retrieval**
The "go find relevant examples" step inside RAG.
*Example:* A search that pulls the three most similar past tasks. The catch: in one experiment it accidentally pulled a task's *own* answer, causing the cheating bug (see *gold leak*).

**Few-shot examples**
A handful of solved examples placed in the prompt to show the model what a good answer looks like.
*Example:* "Here are 3 well-written clarifying-question sets; now write one for this new task." The few examples set the standard.

**Output schema**
A required *shape* for the answer that the model must follow.
*Example:* "Return exactly seven questions, numbered, no preamble." That's a schema — like a form with fixed fields the model has to fill in.

**Chain-of-thought**
Having the model reason step by step, out loud, before committing to a final answer.
*Example:* Instead of blurting an answer, the model first writes "the key unknowns are budget, dates, party size…" then produces its questions — like showing your work on a math problem.

**Multi-step pipeline / multi-call**
Using several model calls in sequence instead of getting the answer in one go.
*Example:* Call 1 drafts the questions, call 2 critiques them, call 3 rewrites — an assembly line rather than a single station.

**Self-critique**
Having the model review and revise its own first draft.
*Example:* "Here's your draft — now find its three weakest questions and improve them." The project found the small model was a poor judge of its own work, so this rarely helped.

**Best-of-N**
Generating several answers and keeping only the best one.
*Example:* Write the email five times, send the strongest. Helpful only if you can reliably tell which is strongest — which the small model struggled to do.

**Voting**
Generating several answers and going with whatever the majority agree on.
*Example:* Ask five times "what's the capital of Australia?", take the most common answer. Good for facts; weaker for open-ended question-writing.

**Tournament**
Pitting candidate answers against each other in head-to-head rounds to crown a winner.
*Example:* A bracket like a sports playoff — answer A beats B, loses to C, and so on, until one survives.

**Ensembles**
Combining several models or several answers rather than relying on a single one.
*Example:* Asking a panel of experts and blending their advice, instead of trusting one person.

**Over-generate-and-prune**
Asking the model for more than you need, then dropping the weakest items.
*Example:* Ask for 8 questions, keep the best 7. This is the trick behind the project's current best score — the spare question lets you cut the weakest without leaving a hole.

**Post-processing**
Automatic clean-up done in plain code *after* the model produces its answer.
*Example:* A script that strips out near-duplicate questions or removes stray emojis — tidying the output without involving the model again.

**Tool use**
Letting the model call a helper function in the middle of answering.
*Example:* Mid-answer, the model calls a "coverage check" function the way you'd reach for a calculator mid-conversation. Available in this project's setup but not yet exploited.

**Topology**
The shape of how the steps and calls are wired together.
*Example:* Whether your pipeline is one straight line, a loop, or a branching tree — that's its topology, like the layout of a subway map.

**Info-gain / value-of-information**
How much a question reduces your uncertainty — choosing the question that teaches you the most.
*Example:* When guessing a number 1–100, "is it above 50?" has high info-gain (rules out half); "is it exactly 7?" usually has low info-gain. Good clarifying questions maximize info-gain.

**Answer-simulation**
Guessing how a user might answer a question, in order to judge which question is most worth asking.
*Example:* Before asking "what's your budget?", the model imagines the likely replies to see whether that answer would actually change the plan.

**Decomposed verification**
Breaking the checking step into several smaller sub-checks instead of one big judgment.
*Example:* Rather than asking "is this answer good?", you ask "is each question on-topic? is any redundant? is anything missing?" separately — easier to get right piece by piece.

---

## Evaluation & measurement

**Rubric**
The fixed scorecard of dimensions used to grade every answer.
*Example:* Like an essay rubric grading grammar, structure, and argument separately. Here the five dimensions are atomicity, specificity, coverage, naturalness, and non-redundancy.

**Gold / gold standard**
The reference "best" answer that everything else is compared against. In this project it's written by Sonnet.
*Example:* The answer key at the back of the textbook. The on-device model's questions are graded against Sonnet's "gold" set for the same task.

**Held-out**
Test items deliberately kept separate and never used in training, so the score stays honest.
*Example:* Like exam questions the students never saw while studying — the only fair way to test whether they actually learned.

**Judge**
An AI set up to score answers automatically by comparing them to the gold.
*Example:* An automated grader. Here, Sonnet plays judge — reading both answers and deciding which is better and why.

**Pairwise / head-to-head**
Comparing two answers directly and picking the better one, rather than scoring each in isolation.
*Example:* A taste test where you sip A and B and say which you prefer — often easier and more reliable than rating each out of 10 alone.

**Win rate / Wins-Ties-Losses (W/T/L)**
How often the model's answer beats the gold across the test cases: Wins, Ties, Losses.
*Example:* "2/5/22" means: of 30 head-to-heads, the on-device model won 2, tied 5, and lost 22 to Sonnet's gold.

**Quality score (0–1)**
The single headline number for an experiment, blending the rubric scores with the win rate.
*Example:* Like a final course grade rolled up from several assignments. 0.28 at the start, 0.44 at the best — higher is better.

**Spec gate / gate**
A hard pass/fail check applied before scoring. Fail it and the case automatically scores zero.
*Example:* A bouncer at the door: the answer must have *exactly* seven questions, a valid title, and no emojis. Six questions? Rejected, zero points — no matter how good they were.

**full-30 / dev-10**
Scoring on all 30 test cases (the honest, final measure) versus a quick 10-case subset (a fast screen).
*Example:* full-30 is the full final exam; dev-10 is a 10-question pop quiz you use to check progress quickly. The project learned to trust only the full exam.

**Proxy**
A cheap stand-in measurement used for quick screening.
*Example:* Weighing yourself daily as a proxy for fitness — fast and convenient, but it can mislead. The 10-case proxy twice showed "wins" that vanished on the full test.

**Leave-one-out**
A safeguard ensuring a test case can never be shown its *own* answer as an example.
*Example:* Covering up the answer to question 5 while you "practice" on it. Without this guard, the model was effectively peeking at the answer key (see *gold leak*).

**Self-consistency**
How often a model agrees with itself when asked the same thing more than once.
*Example:* Ask the same person the same opinion question on two different days; if they answer the same, they're self-consistent. Even Sonnet only agreed with its own "gold" answer about two-thirds of the time — showing the task has real wiggle room.

**Answer-variance**
The natural disagreement between two *equally good* answers — the task genuinely has more than one right response.
*Example:* Two excellent travel agents would ask different (but equally smart) questions about your Paris trip. That spread is answer-variance, not one of them being wrong.

**Regression test**
A re-runnable check that tells you whether something got better or worse over time.
*Example:* A standard health checkup you repeat each year to catch changes. The project's whole setup can be re-run as a regression test when Apple ships a bigger model.

---

## Statistics & analysis

**Area Under the Curve (AUC)**
A score from 0.5 to 1.0 for how well something can tell two groups apart. 0.5 is pure guessing; 1.0 is perfect separation.
*Example:* A spam filter with AUC 0.5 is flipping a coin; 1.0 catches every spam and never flags a real email. The discriminator scored 0.76 on style but only 0.62 on substance — meaning it spotted the model mostly by *how* it wrote, not *what* it asked.

**Latent factor**
A hidden, underlying quality that several visible measurements all secretly reflect.
*Example:* "Athleticism" is latent — you can't measure it directly, but speed, strength, and agility all reflect it. The report found a single hidden "overall quality" factor behind all five rubric scores.

**Variance**
How spread out a set of numbers is.
*Example:* Test scores of 70, 71, 72 have low variance (tightly clustered); 40, 70, 99 have high variance (all over the place).

**Correlation / correlates / co-moves**
How strongly two measurements rise and fall together.
*Example:* Height and shoe size are correlated — taller people tend to have bigger feet. The report found coverage and specificity move together (0.69), so you can't fix one without the other tagging along.

**Gold leak**
The accidental bug where a test case was shown its own gold answer, inflating the score — caught and fixed in this project.
*Example:* A student who accidentally got the answer key before the exam and "scored" a suspicious 99%. The system flagged its own 0.498 result as too good to be real, found the leak, and threw the result out.

---

## Rubric dimensions (defined on-page, but still worth glossing)

**Atomicity**
Whether each question asks exactly one thing.
*Example:* "When and where are you going?" fails atomicity (two questions in one); "When are you going?" passes.

**Specificity**
Whether a question is concrete to *this* task rather than generic filler.
*Example:* "What's your total budget for this trip?" is specific; "Do you have any other preferences?" is generic filler.

**Coverage**
Whether the set of questions includes the most decision-critical unknowns.
*Example:* For a trip, forgetting to ask *which city you're flying from* is a coverage miss — that one answer changes the whole plan. This was the project's stubborn weak spot.

**Naturalness**
Whether the questions read like a thoughtful human wrote them.
*Example:* "What is the main purpose of your visit?" sounds natural; "STATE TRIP OBJECTIVE:" does not.

**Non-redundancy**
Whether the questions avoid overlapping or repeating each other.
*Example:* Asking both "how long will you stay?" and "how many nights?" is redundant — they're the same question twice.

---

## Project coinages (not standard terms — defined here because you can't look them up elsewhere)

**Autoresearch loop**
The self-running cycle in which an AI proposes an experiment, runs it, scores it, and decides whether to keep it — then repeats.
*Example:* Like a scientist who never sleeps: form a hypothesis, test it, write down the result, start again — autonomously, hundreds of times.

**The ruler**
The fixed measuring setup — the 30 gold tasks plus the judge — that is never allowed to change, so scores stay comparable over months.
*Example:* A tape measure you're forbidden to stretch. Bending the ruler to make results look better is the one thing strictly off-limits.

**The agent**
The part of the system that gets changed in each experiment — the prompts, the pipelines, and the fine-tuned adapter.
*Example:* If the ruler is the unchanging exam, the agent is the student — the thing we keep coaching, retraining, and testing against that fixed exam.
