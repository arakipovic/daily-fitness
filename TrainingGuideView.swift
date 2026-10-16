import SwiftUI

// MARK: - Training Guide

struct TrainingGuideView: View {
    var body: some View {
        List {
            Section("Effort & Volume") {
                NavigationLink("Proximity to Failure (RIR)") {
                    TrainingArticleView(article: .failure)
                }
                NavigationLink("How Many Sets per Week?") {
                    TrainingArticleView(article: .volume)
                }
                NavigationLink("Rest Periods") {
                    TrainingArticleView(article: .rest)
                }
                NavigationLink("Rep Ranges") {
                    TrainingArticleView(article: .reps)
                }
            }
            Section("Programming") {
                NavigationLink("Progressive Overload") {
                    TrainingArticleView(article: .overload)
                }
                NavigationLink("Training Frequency") {
                    TrainingArticleView(article: .frequency)
                }
                NavigationLink("Cardio While Lifting") {
                    TrainingArticleView(article: .cardio)
                }
            }
            Section("Technique") {
                NavigationLink("Warming Up") {
                    TrainingArticleView(article: .warmup)
                }
                NavigationLink("Mind-Muscle Connection") {
                    TrainingArticleView(article: .mindMuscle)
                }
                NavigationLink("Exercise Selection") {
                    TrainingArticleView(article: .exerciseSelection)
                }
            }
            Section("Recovery") {
                NavigationLink("Deload Weeks") {
                    TrainingArticleView(article: .deload)
                }
                NavigationLink("Sleep & Performance") {
                    TrainingArticleView(article: .sleep)
                }
                NavigationLink("Muscle Soreness (DOMS)") {
                    TrainingArticleView(article: .doms)
                }
                NavigationLink("NEAT & Daily Movement") {
                    TrainingArticleView(article: .neat)
                }
            }
            Section("Body Composition") {
                NavigationLink("Losing Fat Without Losing Muscle") {
                    TrainingArticleView(article: .muscleOnDiet)
                }
                NavigationLink("Bulking: How Fast to Gain") {
                    TrainingArticleView(article: .bulking)
                }
            }
        }
        .navigationTitle("Training Guide")
        .trackScreen("training_guide")
    }
}

// MARK: - Article model

enum TrainingArticle {
    case failure, volume, rest, reps, overload, frequency, cardio, muscleOnDiet, bulking
    case warmup, mindMuscle, exerciseSelection, deload, sleep, doms, neat

    var title: String {
        switch self {
        case .failure:         return "Proximity to Failure (RIR)"
        case .volume:          return "How Many Sets per Week?"
        case .rest:            return "Rest Periods"
        case .reps:            return "Rep Ranges"
        case .overload:        return "Progressive Overload"
        case .frequency:       return "Training Frequency"
        case .cardio:          return "Cardio While Lifting"
        case .muscleOnDiet:    return "Losing Fat Without Losing Muscle"
        case .bulking:         return "Bulking: How Fast to Gain"
        case .warmup:          return "Warming Up"
        case .mindMuscle:      return "Mind-Muscle Connection"
        case .exerciseSelection: return "Exercise Selection"
        case .deload:          return "Deload Weeks"
        case .sleep:           return "Sleep & Performance"
        case .doms:            return "Muscle Soreness (DOMS)"
        case .neat:            return "NEAT & Daily Movement"
        }
    }

    var sections: [GuideSection] {
        switch self {
        case .failure:         return failureSections
        case .volume:          return volumeSections
        case .rest:            return restSections
        case .reps:            return repsSections
        case .overload:        return overloadSections
        case .frequency:       return frequencySections
        case .cardio:          return cardioSections
        case .muscleOnDiet:    return muscleOnDietSections
        case .bulking:         return bulkingSections
        case .warmup:          return warmupSections
        case .mindMuscle:      return mindMuscleSections
        case .exerciseSelection: return exerciseSelectionSections
        case .deload:          return deloadSections
        case .sleep:           return sleepSections
        case .doms:            return domsSections
        case .neat:            return neatSections
        }
    }
}

struct TrainingArticleView: View {
    let article: TrainingArticle

    var body: some View {
        List {
            ForEach(article.sections) { section in
                VStack(alignment: .leading, spacing: 8) {
                    if let heading = section.heading {
                        Text(heading)
                            .font(.subheadline.weight(.semibold))
                    }
                    Text(section.body)
                        .font(.subheadline)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle(article.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Article content

private let failureSections: [GuideSection] = [
    GuideSection(heading: nil, body: "Training to failure is not required to build muscle. Research consistently shows that stopping 1–3 reps short of failure produces the same hypertrophy — with less fatigue, better recovery, and lower injury risk."),
    GuideSection(heading: "What is RIR?", body: "RIR stands for Reps In Reserve — how many more reps you could have completed before hitting failure.\n\n• 0 RIR = you went to failure\n• 1 RIR = one rep left in the tank\n• 2 RIR = two reps left\n• 3 RIR = three reps left\n\nFor most working sets, aim for 1–3 RIR. The set should feel genuinely hard, but controlled."),
    GuideSection(heading: "Why not always go to failure?", body: "Failure sets reduce your performance on subsequent sets. If you fail set 1, sets 2 and 3 will have fewer reps — meaning less total volume.\n\nExample at the same weight:\n• To failure: 10 / 6 / 3 = 19 total reps\n• 2 RIR stops: 8 / 8 / 8 = 24 total reps\n\nThat's 26% more volume from the same number of sets."),
    GuideSection(heading: "When is failure useful?", body: "Occasional failure on the last set of an isolation exercise (curl, leg extension) helps calibrate what hard actually feels like, making your RIR estimates more accurate.\n\nAvoid failure on heavy compound lifts (squat, deadlift, bench, row). Form breaks down, injury risk rises, and the recovery cost is high."),
]

private let volumeSections: [GuideSection] = [
    GuideSection(heading: nil, body: "Volume — the total number of hard sets per muscle per week — is one of the main drivers of muscle growth. More volume tends to produce more growth, up to your recovery limit."),
    GuideSection(heading: "How many sets?", body: "The evidence supports 10–20 hard sets per muscle per week:\n\n• Beginners: start at ~10 sets and build up over months\n• Intermediate: 12–16 sets works well for most muscles\n• Advanced: up to 20 sets, periodised\n\nA \"hard set\" means 1–3 RIR — genuinely challenging. Easy sets at low effort don't produce the same stimulus."),
    GuideSection(heading: "Volume in a deficit", body: "When eating less, recovery capacity drops. A practical approach during a fat loss phase:\n\n• Reduce total sets by ~20–30% (e.g. 15 → 10 sets per muscle)\n• Keep the load (weight on the bar) the same\n• Maintaining intensity matters more than maintaining volume when calories are low"),
    GuideSection(heading: "More isn't always better", body: "Higher volume gives more growth up to a point, then gains diminish and recovery suffers. Signs you're exceeding your recovery capacity:\n\n• Persistent soreness that doesn't resolve\n• Strength declining week to week\n• Poor sleep and low motivation\n\nIf these appear, cut volume before cutting intensity."),
]

private let restSections: [GuideSection] = [
    GuideSection(heading: nil, body: "Longer rest periods produce more muscle growth. More recovery between sets means each subsequent set is performed at higher quality — more reps, better technique, greater stimulus."),
    GuideSection(heading: "Guidelines by exercise type", body: "• Compound lifts (squat, deadlift, bench, row, overhead press): 2–5 minutes\n• Single-joint isolation (curl, extension, lateral raise): 1–2 minutes\n\nA simple rule: rest long enough that you can match the quality of your previous set."),
    GuideSection(heading: "Practical shortcuts", body: "Short on time? Shorter rest on isolation work costs little. But don't rush heavy compound sets — the extra 90 seconds pays off in more reps and heavier weights on later sets.\n\nSuper-setting antagonist muscles (e.g. biceps + triceps, chest + back) is an efficient way to maintain training quality while cutting session time."),
]

private let repsSections: [GuideSection] = [
    GuideSection(heading: nil, body: "All rep ranges build muscle — provided you're training close to failure. The idea that \"low reps = strength, high reps = muscle\" is largely a myth when effort is matched."),
    GuideSection(heading: "What works", body: "Research shows muscle growth is similar across a wide range:\n\n• Heavy (3–6 reps at high load): builds muscle and strength, high joint stress\n• Moderate (6–12 reps): the practical sweet spot — good for both muscle and strength\n• Light (15–30+ reps): builds muscle too, but sets are more uncomfortable\n\nFor most people, 6–12 reps is where to spend most of your training."),
    GuideSection(heading: "Why 6–12 works best in practice", body: "It's a practical balance:\n• Heavy enough to drive strength adaptations\n• Light enough to recover between sessions\n• Sets finish in a reasonable time\n\nDon't obsess over exact rep counts. A set that's genuinely challenging near failure is what matters — the number is a guide to load selection, not a law."),
]

private let overloadSections: [GuideSection] = [
    GuideSection(heading: nil, body: "Progressive overload is the single most important concept in strength training. Your body adapts to the demands placed on it. When those demands stop increasing, adaptation stops."),
    GuideSection(heading: "How to progress", body: "The two main methods:\n\n1. Add reps — if your target is 6–12 and you hit 12 clean reps, add weight next session\n2. Add weight — increase by the smallest available increment (usually 2.5 kg / 5 lb)\n\nYou don't need to progress every session. Week-to-week progress is the realistic target. After the first year, month-to-month is more realistic."),
    GuideSection(heading: "Other ways to progress", body: "When adding weight or reps isn't possible:\n• Improve range of motion\n• Reduce rest periods slightly\n• Add one extra set\n• Improve technique (same weight, better muscle engagement)\n\nIn a calorie deficit, progress will be slower. Maintaining strength — even holding the same weights — is a sign you're preserving muscle."),
    GuideSection(heading: "Log your workouts", body: "You can't progressively overload what you don't track. Always record the weight and reps for every working set. Progress often feels slow, but the log shows you it's happening."),
]

private let frequencySections: [GuideSection] = [
    GuideSection(heading: nil, body: "Training frequency — how often you train a muscle per week — matters less than total weekly volume. But spreading volume across more sessions tends to produce slightly better results than cramming it into one."),
    GuideSection(heading: "Recommended approach", body: "Aim to train each muscle 2–3 times per week.\n\n• 3 days/week → full-body is ideal\n• 4 days/week → upper/lower split works well\n• 5–6 days/week → push/pull/legs or similar\n\nThis is why full-body and upper/lower splits tend to outperform traditional body-part splits for most people — every muscle gets more frequent stimulation."),
    GuideSection(heading: "Why frequency helps", body: "Muscle protein synthesis — the process of building new muscle tissue — peaks around 24–36 hours after training and returns to baseline by 48–72 hours.\n\nTraining a muscle once a week gives you one stimulus. Training it three times gives three stimuli — more opportunities for growth with the same total volume."),
]

private let cardioSections: [GuideSection] = [
    GuideSection(heading: nil, body: "Moderate cardio doesn't impair muscle growth or strength. The interference effect is mostly a concern at very high volumes or when cardio and lifting are done back-to-back without a break."),
    GuideSection(heading: "What the research shows", body: "A meta-analysis of 43 studies found no interference on muscle growth when cardio and resistance training were combined at moderate volumes. Even strength was unaffected in most comparisons.\n\nExplosive strength (power) was slightly reduced when cardio was done within 3 hours of lifting — but not when sessions were separated by 3+ hours."),
    GuideSection(heading: "Practical guidelines", body: "• Separate cardio and lifting by at least 3 hours when possible\n• Keep cardio moderate — walking, cycling, rowing, swimming\n• Avoid stacking heavy cardio volume on top of 5+ lifting days, especially in a deficit\n• Running 1–2x/week for 20–40 min is compatible with any lifting program\n• Target 7,000–10,000 steps/day — the evidence-based range for health benefits"),
    GuideSection(heading: "Cardio for fat loss", body: "Cardio is not an efficient primary fat loss tool. 30 minutes of walking burns roughly 8g of body fat. It's far easier to create the same deficit by eating less.\n\nUse cardio to support health, maintain NEAT (non-exercise activity), and add modestly to your deficit — not as your main lever. Diet drives fat loss."),
]

private let muscleOnDietSections: [GuideSection] = [
    GuideSection(heading: nil, body: "Losing muscle while dieting is not inevitable. With the right approach, you can preserve — and for beginners, even build — muscle in a calorie deficit."),
    GuideSection(heading: "Three rules", body: "1. Keep lifting with progressive overload\nMuscle needs a reason to stick around. Lifting with progressive overload provides that signal — even in a deficit.\n\n2. Eat enough protein\nAim for 1.6–2.2 g per kg bodyweight (0.7–1 g/lb). Higher protein intakes are more protective as the deficit deepens.\n\n3. Use a moderate deficit\n0.5–1% of bodyweight per week. Larger deficits accelerate muscle loss and are harder to sustain."),
    GuideSection(heading: "What 'lean mass loss' actually means", body: "Reported lean mass loss on scales and DEXA often overstates actual muscle loss. Fat-free mass includes water, glycogen, and connective tissue — not just muscle.\n\nWhen calories and carbs drop at the start of a diet, glycogen and bound water leave first. This shows up as lean mass loss on the scale — but it's not muscle. It reverses when calories normalise."),
    GuideSection(heading: "Managing volume in a deficit", body: "Recovery capacity is lower when you're eating less. A practical adjustment:\n\n• Reduce total sets by ~20–30% (e.g. 15 → 10 sets per muscle)\n• Keep the load (weight on the bar) the same or close to it\n• Don't increase RIR — stay at 1–3\n\nMaintaining strength is the goal. Building it in a deficit is a bonus."),
]

private let bulkingSections: [GuideSection] = [
    GuideSection(heading: nil, body: "Building muscle requires a calorie surplus. The surplus doesn't need to be large — it just needs to be consistent. Most people dramatically overestimate how fast they can gain muscle."),
    GuideSection(heading: "Realistic muscle gain rates", body: "Muscle growth is slow and highly individual:\n\n• Beginner (first year): up to 1–2 kg of muscle per month in ideal conditions\n• Intermediate: 0.5–1 kg per month\n• Advanced: 0.2–0.5 kg per month\n\nGenetic response varies enormously. These are averages, not guarantees."),
    GuideSection(heading: "How much surplus?", body: "Target 0.2–0.5% of bodyweight per week in weight gain.\n\nAt 80 kg: roughly 0.16–0.4 kg (0.35–0.9 lb) per week.\n\nA starting point of 5–10% above maintenance is reasonable (~150–300 extra kcal/day). Larger surpluses add fat faster without meaningfully accelerating muscle gain.\n\nExpect some fat gain — it's unavoidable. Beginners gain a better ratio of muscle to fat than advanced trainees."),
    GuideSection(heading: "When to switch phases", body: "There's no single body fat threshold to switch from building to cutting. A practical approach:\n\n• Start building if you're reasonably lean (men ~12–15% BF, women ~20–25%)\n• Consider cutting when reaching ~18–20% (men) or ~28–30% (women)\n• Stop building sooner if fat gain is bothering you\n\nHigher body fat impairs nutrient partitioning — a larger fraction of the surplus goes to fat rather than muscle."),
]

// MARK: - Warming Up

private let warmupSections: [GuideSection] = [
    GuideSection(heading: nil, body: "A good warm-up improves performance, reduces injury risk, and prepares your nervous system for heavy work. It doesn't need to be long — 10–15 minutes of targeted preparation is sufficient."),
    GuideSection(heading: "General warm-up", body: "Start with 5 minutes of low-intensity movement to raise core temperature and increase blood flow:\n• Rowing, cycling, or walking on a treadmill\n• Jumping jacks, skipping\n\nYou should feel slightly warm but not fatigued."),
    GuideSection(heading: "Exercise-specific warm-up", body: "Before your first heavy compound set, perform 2–3 progressive warm-up sets:\n\nExample — working set of 100 kg squat:\n• Set 1: bar only × 10 (movement rehearsal)\n• Set 2: 60 kg × 5 (light)\n• Set 3: 80 kg × 3 (moderate)\n• Work set: 100 kg × desired reps\n\nWarm-up sets don't count toward your working volume. Keep them fast-moving — long rest between warm-up sets defeats the purpose."),
    GuideSection(heading: "Mobility vs. stretching", body: "Static stretching (holding a stretch for 30+ seconds) before lifting reduces strength and power output by 5–8% — avoid it immediately before heavy sets.\n\nDynamic mobility work (controlled movement through a range of motion) is effective: leg swings, hip circles, shoulder rotations, deep squat holds with movement.\n\nSave static stretching for after the session, when it's useful for long-term flexibility."),
    GuideSection(heading: "Warm-up for subsequent exercises", body: "After warming up for the first exercise, subsequent exercises targeting the same muscle group need less preparation. Isolation exercises after a compound compound lift typically need only 1 light warm-up set.\n\nIf you're switching to a different muscle group entirely, do 1–2 light sets to activate it."),
]

// MARK: - Mind-Muscle Connection

private let mindMuscleSections: [GuideSection] = [
    GuideSection(heading: nil, body: "The mind-muscle connection refers to intentionally focusing on the muscle being trained during a set, rather than just moving the weight from point A to point B. Research shows this focus increases muscle activation — particularly for isolation exercises."),
    GuideSection(heading: "Does it actually work?", body: "Yes, with caveats. Studies measuring EMG (electrical muscle activity) show that:\n\n• Focusing on a specific muscle during curls or flyes increases its activation by 10–15%\n• The effect is strongest for isolation exercises on superficial muscles (biceps, chest, quads)\n• The effect is weaker or absent for compound lifts performed at high loads — at near-maximal effort, the nervous system recruits maximally anyway"),
    GuideSection(heading: "When to use it", body: "• Isolation exercises: always. Curl for the biceps, not just to move the weight up\n• Moderate-load compound sets: useful, especially on the eccentric (lowering) phase\n• Heavy compound sets at RPE 8+: stop thinking about the muscle and focus on technical execution instead\n\nFor hypertrophy training in the 8–15 rep range, a deliberate focus on feeling the target muscle improves results."),
    GuideSection(heading: "Practical tips", body: "• Use a weight you can control — connection breaks down when load is too heavy\n• Slow the eccentric (lower in 2–3 seconds) — this is where muscle damage and growth stimulus are highest\n• Touch the muscle with your hand between sets — proprioception helps establish the connection\n• Watch the muscle work in a mirror for new exercises — visual feedback reinforces neural connection"),
]

// MARK: - Exercise Selection

private let exerciseSelectionSections: [GuideSection] = [
    GuideSection(heading: nil, body: "Exercise selection matters, but less than most people think. The best exercise is the one you can load progressively, perform with good technique, and tolerate joint-wise over years — not the one a study says is optimal."),
    GuideSection(heading: "Compound vs isolation", body: "Compound exercises (squat, deadlift, bench, row, overhead press, pull-up) train multiple muscle groups simultaneously and allow the most progressive overload. They should form the core of any program.\n\nIsolation exercises (curl, extension, lateral raise, fly) target individual muscles and allow fine-tuning of weak points or aesthetics. They're supplements to, not replacements for, compound work.\n\nA typical ratio: 60–70% compound, 30–40% isolation."),
    GuideSection(heading: "Free weights vs machines", body: "Both build muscle effectively. Research shows similar hypertrophy between matched machine and free weight training.\n\nFree weights:\n• Greater stabiliser demand and real-world carry-over\n• Higher technical learning curve\n• More injury risk when technique breaks down\n\nMachines:\n• Isolate the target muscle more effectively\n• Safer at high fatigue or near failure\n• Ideal for injury-conscious training and pump-focused work\n\nUse both. Compound free weight movements for the main lifts; machines for accessories."),
    GuideSection(heading: "Exercise variation", body: "Changing exercises every session or every week provides no meaningful benefit. The nervous system needs repeated exposure to a movement to become efficient at it — which is part of how you get stronger.\n\nChange exercises when:\n• You've stopped progressing despite good effort and recovery\n• The exercise causes joint pain that doesn't resolve\n• You've been running the same variation for 12–16 weeks\n\nMinor variations (close vs wide grip, incline vs flat) provide variety without losing the benefits of practiced movement patterns."),
    GuideSection(heading: "The best exercises, simply", body: "For most people, a program built around these movements covers everything:\n\nLower: Squat or leg press, Romanian deadlift or leg curl, hip thrust\nUpper push: Bench press or dumbbell press, overhead press, dip or incline press\nUpper pull: Row (barbell, cable, or dumbbell), pull-up or lat pulldown\nCore: Plank, dead bug, pallof press\n\nEverything else is accessory work layered on top."),
]

// MARK: - Deload Weeks

private let deloadSections: [GuideSection] = [
    GuideSection(heading: nil, body: "A deload is a planned period of reduced training stress — typically one week — where intensity or volume drops significantly. Done correctly, it accelerates recovery and returns you to training stronger."),
    GuideSection(heading: "Why deload?", body: "Training accumulates fatigue over weeks. Fatigue masks fitness — you're fitter than you feel when tired. A deload dissipates fatigue without losing the underlying adaptations.\n\nSigns you need a deload:\n• Strength declining for 2+ weeks despite eating and sleeping well\n• Persistent joint aches and muscle soreness that doesn't clear between sessions\n• No motivation to train — dreading the gym\n• Poor sleep quality (even when training is done)\n\nYou don't need to feel destroyed to benefit from a deload. Planned deloads prevent reaching that point."),
    GuideSection(heading: "When to deload", body: "Two approaches:\n\n1. Planned: every 4–8 weeks. More frequent if training is intense (5+ days/week, near failure most sessions). Less frequent if training is moderate.\n\n2. Autoregulated: when the signs above appear.\n\nBeginners may not need formal deloads for the first 6–12 months. Fatigue accumulates slower with lower starting volumes."),
    GuideSection(heading: "How to deload", body: "Two common methods:\n\nVolume deload (preferred):\n• Keep weights the same\n• Reduce sets to ~50% of normal volume\n• Maintain movement quality and intensity\n\nIntensity deload:\n• Keep volume similar\n• Reduce load to ~60–70% of normal\n\nAvoid stopping training entirely — complete rest can cause unexpected soreness and a loss of the 'groove' in movement patterns."),
    GuideSection(heading: "Deloads and fat loss phases", body: "During a calorie deficit, recovery capacity is lower. More frequent deloads (every 4–6 weeks) are appropriate.\n\nA diet break (eating at maintenance for 1–2 weeks) can be combined with a deload — this addresses both metabolic adaptation and physical recovery simultaneously."),
]

// MARK: - Sleep & Performance

private let sleepSections: [GuideSection] = [
    GuideSection(heading: nil, body: "Sleep is the most powerful recovery tool available. No supplement, protocol, or training technique compensates for consistently poor sleep. If you're training hard and sleeping poorly, you're leaving a large fraction of your results on the table."),
    GuideSection(heading: "What sleep deprivation does to your training", body: "Even one night of poor sleep measurably impairs:\n• Maximum strength output (down 5–20%)\n• Reaction time and coordination\n• Time to exhaustion in endurance tasks\n• Motivation and perceived effort\n\nChronic sleep restriction accelerates muscle loss during a calorie deficit and reduces muscle gain in a surplus. It also increases appetite — by up to 30–40% — making dieting harder."),
    GuideSection(heading: "Sleep and body composition", body: "Studies on fat loss show that sleep-deprived dieters lose significantly more lean mass and less fat compared to well-rested dieters on the same calorie deficit.\n\nA landmark study (Nedeltcheva 2010) found that reducing sleep from 8.5 to 5.5 hours while in a deficit:\n• Reduced fat mass loss by 55%\n• Increased lean mass loss by 60%\n\nSleep isn't a passive state — it's when growth hormone is secreted and muscle protein synthesis peaks."),
    GuideSection(heading: "How much sleep?", body: "Most adults need 7–9 hours. Athletes in intense training phases often need 9–10 hours.\n\nThe quality matters as much as quantity:\n• Deep sleep (stage 3) is where physical restoration happens\n• REM sleep is where cognitive function and mood are restored\n\nYou can view your sleep stages in the Health tab of this app (after granting HealthKit access)."),
    GuideSection(heading: "Practical sleep hygiene", body: "• Keep a consistent sleep and wake time — even on weekends\n• Keep your bedroom cool (16–19°C / 60–67°F is optimal for most people)\n• Stop caffeine at least 8 hours before bed (pre-workout: 12–13 hours)\n• Avoid screens 30–60 minutes before bed, or use blue light filtering\n• Alcohol impairs sleep architecture even in small amounts — avoid it within 2–3 hours of bed\n• Blackout curtains and white noise are among the most effective environmental changes"),
]

// MARK: - Muscle Soreness (DOMS)

private let domsSections: [GuideSection] = [
    GuideSection(heading: nil, body: "DOMS — Delayed Onset Muscle Soreness — is the muscle soreness that peaks 24–48 hours after training. It's common, normal, and frequently misunderstood."),
    GuideSection(heading: "What causes DOMS?", body: "DOMS is caused by microscopic muscle damage from unfamiliar exercise — particularly the eccentric (lowering) phase. This triggers inflammation and repair processes.\n\nIt's most pronounced after:\n• Starting a new program or returning from a break\n• Introducing a new exercise or movement pattern\n• Significantly increasing volume or intensity\n\nDOMS decreases rapidly as your body adapts to a stimulus. Experienced lifters doing their normal program rarely feel significant DOMS."),
    GuideSection(heading: "Does soreness mean muscle growth?", body: "No. Soreness is not a reliable indicator of an effective workout or muscle growth stimulus.\n\n• You can have an excellent stimulus with no soreness\n• You can be very sore with minimal growth stimulus\n• Advanced lifters rarely get sore from their normal training — this doesn't mean they're not growing\n\nThe primary drivers of hypertrophy are mechanical tension and progressive overload — not muscle damage or soreness."),
    GuideSection(heading: "Should you train through DOMS?", body: "Generally yes — mild to moderate DOMS doesn't impair performance significantly. Active recovery (light movement, blood flow) actually helps it resolve faster.\n\nIf soreness is severe:\n• Reduce intensity (load and volume) for that session\n• Focus on technique and control\n• Don't skip the session — inactivity prolongs DOMS\n\nDOMS in a muscle doesn't mean it's not recovered enough to train — it means the repair process is ongoing, which is normal."),
    GuideSection(heading: "Managing DOMS", body: "Most interventions are modestly effective at best:\n\n• Cold water immersion (ice bath): reduces perceived soreness, some evidence for reduced strength loss\n• Massage or foam rolling: reduces perception of soreness; limited effect on actual recovery\n• Active recovery (light cardio, walking): improves blood flow and clears metabolic byproducts\n• Sleep: the most effective recovery tool available\n• Adequate protein intake: supports repair\n\nDon't train hard on a severely sore muscle if it affects technique — injury risk rises when movement is compromised."),
]

// MARK: - NEAT & Daily Movement

private let neatSections: [GuideSection] = [
    GuideSection(heading: nil, body: "NEAT stands for Non-Exercise Activity Thermogenesis — the calories burned from all movement that isn't formal exercise: walking, fidgeting, standing, household tasks, typing.\n\nNEAT is highly variable between individuals and is one of the main reasons two people with the same body weight can have very different calorie needs."),
    GuideSection(heading: "Why NEAT matters for fat loss", body: "An active person might burn 600–800 kcal/day more from NEAT than a sedentary person of the same weight. This difference is larger than most formal exercise sessions.\n\nWhen you reduce calories, NEAT often drops unconsciously — you move less, sit more, fidget less. This is a major driver of plateaus. You may be eating the same and still stalling because you're burning 200–300 fewer calories through reduced movement."),
    GuideSection(heading: "Steps as a proxy for NEAT", body: "Daily step count is the easiest way to track and increase NEAT. The evidence-based targets:\n\n• 7,000 steps/day: associated with significant reductions in all-cause mortality\n• 8,000–10,000 steps/day: optimal for most health outcomes\n• 10,000+ steps: additional benefit, but diminishing returns\n\nYou can track your daily steps in the Health tab of this app."),
    GuideSection(heading: "How to increase NEAT without thinking about it", body: "• Walk or cycle for short errands instead of driving\n• Take stairs instead of lifts\n• Stand or walk during phone calls\n• Get off public transport one stop early\n• Walk during lunch breaks\n• Set a timer to stand or move every hour if you work at a desk\n\nThese add up to hundreds of extra calories per day without any perceived effort."),
    GuideSection(heading: "NEAT and training", body: "Intense training days can actually reduce NEAT — your body compensates by reducing spontaneous movement. This is one reason adding more gym sessions doesn't always accelerate fat loss as much as expected.\n\nProtect your steps on training days — getting 8,000 steps in addition to lifting is more effective for fat loss than adding another gym session to 4,000 daily steps."),
]
