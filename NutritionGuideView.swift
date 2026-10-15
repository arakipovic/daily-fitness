import SwiftUI

// MARK: - Top-level Guide

struct NutritionGuideView: View {
    var body: some View {
        List {
            Section("Tracking Basics") {
                NavigationLink("Part 1 · The Case for Tracking Macros") {
                    GuidePartView(part: .part1)
                }
                NavigationLink("Part 2 · Reading Nutrition Labels") {
                    GuidePartView(part: .part2)
                }
                NavigationLink("Part 3 · Tracking Without a Label") {
                    GuidePartView(part: .part3)
                }
                NavigationLink("Part 4 · Weighing Your Food") {
                    GuidePartView(part: .part4)
                }
                NavigationLink("Part 5 · Simplified Macro Rules") {
                    SimplifiedMacroRulesView()
                }
            }
            Section("Fat Loss") {
                NavigationLink("Fat Loss Fundamentals") {
                    GuidePartView(part: .fatLoss)
                }
                NavigationLink("Hunger & Satiety") {
                    GuidePartView(part: .hunger)
                }
                NavigationLink("Diet Breaks & Refeeds") {
                    GuidePartView(part: .dietBreaks)
                }
                NavigationLink("Eating Out & Social Eating") {
                    GuidePartView(part: .eatingOut)
                }
            }
            Section("Nutrition Science") {
                NavigationLink("Protein & Muscle") {
                    GuidePartView(part: .protein)
                }
                NavigationLink("Fiber") {
                    GuidePartView(part: .fiber)
                }
                NavigationLink("Meal Timing & Fasting") {
                    GuidePartView(part: .mealTiming)
                }
                NavigationLink("Reading the Scale") {
                    GuidePartView(part: .scale)
                }
                NavigationLink("Supplements Worth Taking") {
                    GuidePartView(part: .supplements)
                }
            }
        }
        .navigationTitle("Nutrition Guide")
    }
}

// MARK: - Static guide parts

enum GuidePart {
    case part1, part2, part3, part4
    case fatLoss, protein, scale, supplements
    case hunger, eatingOut, dietBreaks, fiber, mealTiming

    var title: String {
        switch self {
        case .part1: return "The Case for Tracking Macros"
        case .part2: return "Reading Nutrition Labels"
        case .part3: return "Tracking Without a Label"
        case .part4: return "Weighing Your Food"
        case .fatLoss: return "Fat Loss Fundamentals"
        case .protein: return "Protein & Muscle"
        case .scale: return "Reading the Scale"
        case .supplements: return "Supplements Worth Taking"
        case .hunger: return "Hunger & Satiety"
        case .eatingOut: return "Eating Out & Social Eating"
        case .dietBreaks: return "Diet Breaks & Refeeds"
        case .fiber: return "Fiber"
        case .mealTiming: return "Meal Timing & Fasting"
        }
    }

    var sections: [GuideSection] {
        switch self {
        case .part1: return part1Sections
        case .part2: return part2Sections
        case .part3: return part3Sections
        case .part4: return part4Sections
        case .fatLoss: return fatLossSections
        case .protein: return proteinSections
        case .scale: return scaleSections
        case .supplements: return supplementsSections
        case .hunger: return hungerSections
        case .eatingOut: return eatingOutSections
        case .dietBreaks: return dietBreaksSections
        case .fiber: return fiberSections
        case .mealTiming: return mealTimingSections
        }
    }
}

struct GuideSection: Identifiable {
    let id = UUID()
    let heading: String?
    let body: String
}

// MARK: - Tracking content

private let part1Sections: [GuideSection] = [
    GuideSection(heading: nil, body: "The number one reason people struggle to lose fat (or gain muscle) is because they're eating too much — or not enough. People are notoriously bad at estimating food intake, often underreporting by 30–50%.\n\nCalorie tracking makes the invisible visible. It doesn't have to be forever — even a few weeks of accurate tracking changes how you see food."),
    GuideSection(heading: "Accuracy isn't the point", body: "Food labels can be off by up to 20%, and restaurant meals often have far more calories than listed. This is fine. Consistency matters far more than precision.\n\nTracking provides a consistent baseline. Being off by 10% but making progress beats being off by 100% with no idea why you're stuck."),
    GuideSection(heading: "Recommended apps", body: "Download a calorie tracking app. Two good options:\n\n• MyFitnessPal (iOS & Android)\n• FatSecret (iOS & Android)\n\n⚠️ Do NOT connect your activity tracker to the app — it will start deducting exercise calories from your food intake, which you don't want."),
]

private let part2Sections: [GuideSection] = [
    GuideSection(heading: nil, body: "Nutrition labels help you get a snapshot of the calorie and macro composition of different foods. The only fields you need to pay attention to are:\n\n• Serving size\n• Calories\n• Total fat\n• Total carbs\n• Protein\n\nUnless you have a health condition requiring it, ignore everything else (sodium, cholesterol, etc)."),
    GuideSection(heading: "Net carbs — ignore this", body: "Some products (especially protein bars) list 'net carbs' or 'impact carbs'. This refers to digestible carbs only. Ignore the term — just track the Total Carbs listed on the label. Your tracking app will do the same."),
    GuideSection(heading: "How to track food with a label", body: "1. Open the barcode scanner in your app\n2. Scan the barcode on the packaging\n3. Confirm the macros match the label\n4. Save to diary\n\nIf the barcode doesn't work, search for the food manually. If it's not in the database, add it as a new food item — it only takes a few seconds and it'll be there forever."),
]

private let part3Sections: [GuideSection] = [
    GuideSection(heading: "Single-ingredient foods", body: "A single-ingredient food has only one ingredient: fruits, vegetables, beans, potatoes, rice, meat.\n\nTo track:\n1. Weigh the food on your scale\n2. Search for it in your app\n3. Select the relevant entry\n4. Enter the weight\n5. Save to diary"),
    GuideSection(heading: "Restaurant foods (posted calories)", body: "Most popular chains are in your tracking app. Search for the food, select it, save to diary.\n\nIf it's not in the app, search Google for '[restaurant name] + nutrition info'. Most restaurants now publish their nutrition info online. Once you have the numbers, add a custom food to your app."),
    GuideSection(heading: "Restaurant foods (no posted calories)", body: "Option 1: Find a similar item from a well-known chain and use that instead. E.g. if you're at a gourmet burger place, look up a comparable Five Guys burger.\n\nOption 2: Track the ingredients separately. For a grilled chicken + rice meal, guesstimate the portions and track each ingredient individually.\n\n⚠️ Pro-tip: look up the menu ahead of time and add your meal to your tracking app the morning of or the day before."),
]

private let part4Sections: [GuideSection] = [
    GuideSection(heading: "Raw vs cooked", body: "Always weigh and track your food in the raw/uncooked state before cooking. Cooking changes the weight of food, which changes its calorie and macro profile.\n\nIf you do track cooked food (e.g. you bought pre-cooked chicken), weigh it cooked and make sure to search for the 'cooked' version in your app.\n\nThe key rule: always track the food in the state you weighed it."),
    GuideSection(heading: "Using your scale", body: "Put the food on the scale, tare (zero) it, then weigh your portion.\n\nFor things like peanut butter from a jar: put the jar on the scale, set the scale to zero, then take out what you need. The scale will show a negative number — that's how much you used."),
]

// MARK: - Science & Strategy content

private let fatLossSections: [GuideSection] = [
    GuideSection(heading: nil, body: "Fat loss comes down to one thing: consuming less energy than you burn. Everything else — food type, meal timing, supplements — works by influencing your intake, expenditure, or how well you stick to your plan.\n\nGet the fundamentals right and the details take care of themselves."),
    GuideSection(heading: "How fast should you lose weight?", body: "Aim for 0.5–0.7% of your bodyweight per week. At 80 kg, that's roughly 0.4–0.55 kg (about 1 lb) per week.\n\nFaster rates — above 1% per week — increase muscle loss and are much harder to sustain. Slower rates produce better body composition results and are far more likely to stick."),
    GuideSection(heading: "When to adjust your calories", body: "Don't react to single weigh-ins. Take the weekly average and compare week to week.\n\nGive any change 3–4 weeks before deciding if it's working. If the weekly average isn't moving:\n\n1. Check your intake first — hidden calories in sauces, oils, and snacks add up fast\n2. Cut 5–10% of total calories (e.g. 2,000 → 1,800 kcal)\n3. Increase daily steps before cutting food further\n\nLeave protein untouched when adjusting. Reduce carbs or fat."),
    GuideSection(heading: "One bad day won't ruin your progress", body: "Real fat gain requires a sustained surplus over days or weeks. 1 kg of fat stores around 7,700 kcal — a single large meal can't cause that.\n\nThe spike after a big dinner is water, glycogen, sodium, and food in transit. It reverses within 48 hours. The real risk isn't the meal — it's the guilt spiral that follows, leading to restriction and overeating cycles."),
    GuideSection(heading: "Flexible beats rigid", body: "Diets with rigid rules (\"no carbs\", \"clean foods only\", exact gram targets) have worse long-term adherence than flexible approaches (calorie ranges, 80/20 food quality, planned higher-calorie days).\n\nHow closely you stick to your plan predicts results far better than which diet you follow. A 90%-adherent plan beats a \"perfect\" plan you quit in three weeks."),
]

private let proteinSections: [GuideSection] = [
    GuideSection(heading: nil, body: "Protein is the most important macro for body composition. It preserves muscle in a deficit, builds muscle in a surplus, keeps you fuller for longer, and burns more calories during digestion than any other nutrient."),
    GuideSection(heading: "How much protein?", body: "The evidence points to 1.6–2.2 g per kg of bodyweight per day (roughly 0.7–1 g per lb).\n\n• Fat loss phase: aim for the higher end (2.0–2.2 g/kg)\n• Maintenance or building: 1.6–2.0 g/kg is sufficient\n• Practical default: 1 g per lb of bodyweight\n\nFor a 75 kg person: 120–165 g of protein per day."),
    GuideSection(heading: "Will I lose muscle when dieting?", body: "Not if you do three things:\n\n1. Keep lifting — progressive overload is the primary signal to retain muscle\n2. Eat enough protein — 1.6+ g/kg is protective\n3. Use a moderate deficit — 0.5–1% bodyweight/week\n\nMost apparent \"lean mass loss\" on a scale is water and glycogen, not muscle tissue. It comes back when calories normalise."),
    GuideSection(heading: "Protein keeps you full", body: "Protein has the highest thermic effect of any macro — roughly 20–30% of its calories are used in digestion. 100 kcal of protein nets roughly 70–80 kcal.\n\nHigh-protein meals suppress hunger hormones more effectively than high-carb or high-fat meals. This is a major reason high-protein diets work — you naturally eat less without trying."),
    GuideSection(heading: "Does timing matter?", body: "Total daily protein matters far more than timing. The window for muscle protein synthesis is roughly 24 hours, not 30 minutes.\n\nSpread protein across 3–5 meals for practical purposes. Research shows that even large single-meal doses of protein (100g+) are absorbed and used — just more slowly. Getting the total right is what counts."),
]

private let scaleSections: [GuideSection] = [
    GuideSection(heading: nil, body: "Your scale weight is not your fat mass. It's fat + muscle + bone + water + glycogen + food in transit — everything in your body at once.\n\nFat changes slowly. Most of what you see day to day is everything else fluctuating."),
    GuideSection(heading: "What causes daily swings?", body: "Normal fluctuations of 1–3 kg (2–6 lb) over a single day are expected. Common causes:\n\n• Carbohydrates: each gram of glycogen binds ~3–4g of water. A high-carb day can add 400–800g overnight\n• Sodium: causes temporary water retention\n• Late meals: food still moving through your digestive system\n• Stress and poor sleep: raise cortisol, causing short-term water retention\n• Menstrual cycle: can shift weight 1–3 kg across the month"),
    GuideSection(heading: "How to use the scale correctly", body: "Weigh yourself daily, under the same conditions:\n• Morning, after bathroom, before eating or drinking\n\nIgnore individual readings. Take the weekly average and compare it to the previous week's average. That's your signal.\n\nA single number tells you almost nothing. A week-on-week trend tells you everything."),
    GuideSection(heading: "Other progress markers", body: "The scale is one data point. Use these alongside it:\n\n• Waist measurement with a tape — responds to fat loss and is less affected by water and glycogen\n• Progress photos — every 2–4 weeks, same time of day, same lighting\n• How your clothes fit\n• Gym performance — maintaining or improving strength in a deficit is a sign you're preserving muscle\n• Energy levels and sleep quality"),
    GuideSection(heading: "What counts as progress?", body: "You're on track if, over a 2–4 week period:\n\n• Weekly weight average is trending down (fat loss) or up slowly (building)\n• Waist is stable or shrinking\n• Strength is maintained or improving\n• Energy and sleep are reasonable\n\nIf the scale stalls but the waist is shrinking and you're getting stronger — that's progress. Trust the full picture, not one number."),
]

private let supplementsSections: [GuideSection] = [
    GuideSection(heading: nil, body: "Most supplements are not worth the money. The fitness industry is built on overpromising and underdelivering. These four have genuine, well-replicated evidence. Everything else is optional at best."),
    GuideSection(heading: "Creatine monohydrate — 5g/day", body: "The most researched supplement in existence. Taking 5g/day consistently adds 0.8–1 kg of lean mass over 8–12 weeks of training, and reliably improves strength across all rep ranges.\n\nSafe at any age. No loading phase is needed. Timing doesn't matter much — take it at any point in the day. Plain creatine monohydrate is as effective as any more expensive form (Kre-Alkalyn, HCl, etc.). Don't overpay."),
    GuideSection(heading: "Protein powder", body: "Useful when it's inconvenient to hit your protein target from whole food. Whey has the best amino acid profile and is rapidly absorbed.\n\nDon't count collagen toward your protein target. It lacks tryptophan and is low in leucine — the key amino acid for muscle synthesis. Studies show it's significantly inferior to whey for muscle.\n\nAim to get most protein from whole foods. Protein powder is a convenient supplement, not a foundation."),
    GuideSection(heading: "Caffeine — 3–6 mg/kg", body: "Improves both strength and endurance performance. No need to cycle off — tolerance to caffeine doesn't blunt its training benefit.\n\nThe main concern is sleep. Allow enough clearance time:\n• Coffee (~110mg): stop 8–9 hours before bed\n• Pre-workout (~220mg): stop 12–13 hours before bed\n\nFor a 10pm bedtime — coffee before 1–2pm, pre-workout before 9–10am."),
    GuideSection(heading: "Vitamin D (if deficient)", body: "Most people who work indoors or live in northern climates are deficient. Vitamin D supports immune function, bone health, and mood.\n\n1,000–2,000 IU daily is a safe, practical dose. Fish oil (EPA+DHA ~250–500mg/day) is worth considering for cardiovascular health if you don't eat fatty fish 2–3x per week."),
    GuideSection(heading: "What to skip", body: "• BCAAs — redundant if you're hitting your protein target from food or protein powder\n• Fat burners — no meaningful evidence of fat loss beyond a calorie deficit\n• Collagen protein — poor amino acid profile, don't count it toward protein\n• Glutamine — no benefit for healthy people in normal training\n• Electrolyte drinks — unnecessary unless doing ultra-endurance events or strict keto"),
]

// MARK: - Hunger & Satiety

private let hungerSections: [GuideSection] = [
    GuideSection(heading: nil, body: "Hunger is the biggest obstacle in a fat loss diet. Managing it well is the difference between a diet you can sustain and one you abandon after a month. You don't need to white-knuckle it — understanding why hunger spikes lets you engineer your eating to suppress it."),
    GuideSection(heading: "Protein is the most satiating macro", body: "Gram for gram, protein blunts hunger more than carbs or fat. It suppresses ghrelin (the hunger hormone) and raises satiety hormones (GLP-1, PYY, CCK) more effectively than any other macro.\n\nPractical implication: build every meal around a protein source. Not as an afterthought — first. High-protein breakfasts significantly reduce calorie intake for the rest of the day."),
    GuideSection(heading: "Food volume matters more than calories", body: "Stomach stretch receptors signal fullness — what matters to them is volume, not calories. 500 kcal of oil fills the stomach far less than 500 kcal of vegetables.\n\nHigh-volume, low-calorie foods:\n• Leafy greens, cucumber, celery (almost zero calories)\n• Fruit — mostly water\n• Potatoes — among the most satiating foods per calorie\n• Oats — absorb water, expand in the stomach\n• Soups — liquid bulk increases satiety\n\nAdding large portions of fibrous vegetables to every meal is a near-costless way to eat more and feel fuller."),
    GuideSection(heading: "Liquid calories barely register", body: "Drinks don't trigger the same stretch receptors as solid food. Juice, smoothies, milk, and alcohol contain real calories but don't produce the same satiety as solid food of equivalent calories.\n\nThis is why drinking your calories is so easy to overdo. If you're trying to control intake:\n• Prioritise whole food sources of nutrition\n• Use drinks to hydrate, not to fuel\n• Coffee and tea (unsweetened) are excellent for appetite suppression"),
    GuideSection(heading: "Fibre slows everything down", body: "Dietary fibre slows gastric emptying — food stays in your stomach longer and you stay fuller. Soluble fibre (oats, beans, lentils, apples) forms a gel that further slows digestion and helps stabilise blood sugar.\n\nAim for 25–35g of fibre per day. Most people eating a standard Western diet get less than half of this."),
    GuideSection(heading: "Practical hunger management", body: "• Eat protein at every meal — minimum 30–40g per meal where possible\n• Fill half your plate with non-starchy vegetables\n• Drink water before and during meals — 500ml before a meal reduces intake by ~13%\n• Space meals evenly — going too long without eating makes hunger harder to control\n• Sleep enough — sleep deprivation raises ghrelin and lowers leptin, making hunger feel 30–40% more intense"),
]

// MARK: - Eating Out & Social Eating

private let eatingOutSections: [GuideSection] = [
    GuideSection(heading: nil, body: "Eating out doesn't have to derail your diet. It can be managed with a few simple strategies. The goal isn't perfection — it's damage control and consistency over the whole week."),
    GuideSection(heading: "Plan ahead when you can", body: "Look at the menu online before you go. Decide what you'll eat beforehand so you're making the decision when you're not hungry and not in a social situation.\n\nLog the meal in your tracking app in the morning. Seeing the calories committed to your diary makes it easier to stay honest. It also lets you adjust the rest of your day around it."),
    GuideSection(heading: "Lower-calorie ordering strategies", body: "• Ask for sauces and dressings on the side — a salad with dressing can have as many calories as a burger\n• Choose grilled or baked over fried\n• Swap sides: fries → salad or vegetables (saves 300–500 kcal)\n• Skip or share starters and desserts\n• Avoid liquid calories — skip the soft drink, juice, or alcoholic drinks if you're calorie-limited\n• Skip the bread basket"),
    GuideSection(heading: "How to estimate when you can't track exactly", body: "When you have no nutritional information, use comparison foods:\n\n• Pasta dish at a restaurant ≈ 700–1,200 kcal depending on sauce\n• Burger and fries ≈ 900–1,400 kcal\n• Sushi (12 pieces) ≈ 500–700 kcal\n• Grilled chicken + vegetables ≈ 400–600 kcal\n• Pizza (2 average slices) ≈ 500–700 kcal\n\nWhen in doubt, overestimate. People consistently underestimate restaurant meals by 30–50%."),
    GuideSection(heading: "Social eating and events", body: "One meal or one evening won't derail your progress. Weekly calorie balance is what matters — not daily perfection.\n\nA practical approach for a social night:\n• Eat a high-protein meal before you go (reduces hunger and impulse decisions)\n• Eat lightly for the rest of that day\n• Don't try to undo it the next day with severe restriction — return to your normal pattern instead\n\nDiets fail when people let one bad day cascade into a week. The meal isn't the problem — the aftermath is."),
    GuideSection(heading: "Alcohol", body: "Alcohol provides 7 kcal per gram — almost as calorie-dense as fat. A single evening of drinking can add 500–1,500 kcal that don't suppress appetite or provide satiety.\n\nIf you drink, compensate by reducing carbs or fat — not protein — that day. Use the Alcohol Macro Adjuster in this app to see the numbers."),
]

// MARK: - Diet Breaks & Refeeds

private let dietBreaksSections: [GuideSection] = [
    GuideSection(heading: nil, body: "Extended calorie restriction causes metabolic adaptation — your body reduces energy expenditure over time to resist fat loss. Diet breaks and refeeds are structured periods of higher calorie intake designed to partially counteract this."),
    GuideSection(heading: "What is a refeed?", body: "A refeed is 1–3 days of eating at or slightly above maintenance, with carbohydrates as the primary addition. Protein stays high. Fat stays low.\n\nThe purpose:\n• Replenish muscle glycogen (improves training performance)\n• Temporarily restore leptin (the satiety hormone that drops during dieting)\n• Provide a mental break from restriction\n• Reduce cortisol elevated by chronic deficit\n\nA refeed is planned — not a cheat day. The difference matters."),
    GuideSection(heading: "What is a diet break?", body: "A diet break is 1–2 weeks of eating at maintenance — not a surplus, not a deficit. Weight stays stable.\n\nDiet breaks are useful when:\n• You've been dieting for 12+ weeks continuously\n• Motivation and adherence are declining\n• Performance in the gym has dropped significantly\n• You're very lean (sub-12% for men, sub-20% for women) and losing speed is slow\n\nAfter a diet break, the diet resumes and fat loss continues. The break doesn't undo progress."),
    GuideSection(heading: "Does metabolic adaptation matter?", body: "Yes, but it's often overstated. After significant weight loss, total daily energy expenditure can drop 10–15% beyond what's explained by the weight loss alone. This is real, but it rarely stops fat loss completely.\n\nThe bigger issue is usually:\n• Untracked calorie creep (portions growing back)\n• NEAT reduction (moving less without realising it)\n• Declining dietary adherence over months\n\nDiet breaks help with all of these — particularly adherence."),
    GuideSection(heading: "Cheat days vs refeeds", body: "A cheat day — where anything goes — is not a refeed. An uncontrolled cheat day typically adds 2,000–5,000+ extra calories, erasing a week of deficit.\n\nA refeed:\n• Has a specific calorie target (maintenance ± 10%)\n• Focuses on carbohydrate increases (rice, potato, fruit, oats)\n• Keeps protein high and fat controlled\n• Is planned, not impulsive\n\nIf the idea of a refeed appeals to you, use the structure. If you want a mental break from counting, a diet break at maintenance is a better option than an untracked cheat."),
]

// MARK: - Fiber

private let fiberSections: [GuideSection] = [
    GuideSection(heading: nil, body: "Fibre is one of the most underappreciated tools in fat loss. Most people eating a typical Western diet get 10–15g per day. The target for body composition and health is 25–40g."),
    GuideSection(heading: "Why fibre helps with fat loss", body: "• Slows gastric emptying — food stays in the stomach longer, satiety lasts longer\n• Blunts blood sugar spikes — reduces insulin response and subsequent hunger\n• Feeds gut bacteria — produces short-chain fatty acids that support metabolism\n• Adds bulk without calories — fibre itself provides 0–2 kcal/g vs 4 kcal/g for digestible carbs"),
    GuideSection(heading: "Soluble vs insoluble", body: "Soluble fibre dissolves in water and forms a gel:\n• Oats, barley, beans, lentils, apples, citrus, psyllium husk\n• Most beneficial for satiety and blood sugar management\n\nInsoluble fibre doesn't dissolve and adds bulk:\n• Whole grains, wheat bran, vegetables, nuts\n• Supports gut motility and digestive health\n\nYou don't need to track both separately. Focus on total daily fibre and eat a variety of sources."),
    GuideSection(heading: "Target and sources", body: "Aim for 25–35g per day. A practical breakdown:\n\n• 1 cup cooked oats: ~4g\n• 1 cup cooked lentils: ~15g\n• 1 medium apple: ~4g\n• 1 cup broccoli: ~5g\n• 1 tbsp psyllium husk: ~7g\n• 2 slices wholegrain bread: ~4g\n\nIf you're currently eating very little fibre, increase gradually over 2–3 weeks. A sudden large increase causes bloating and GI discomfort."),
    GuideSection(heading: "Tracking fibre", body: "Your calorie tracking app will show fibre for most foods. Track it like any other macro — the goal is 25g minimum, 35g or more ideally.\n\nHigh-fibre intake is associated with lower body weight independent of calories. It's not magic — it works by making it easier to eat less, improving satiety, and supporting gut health."),
]

// MARK: - Meal Timing & Fasting

private let mealTimingSections: [GuideSection] = [
    GuideSection(heading: nil, body: "Meal timing — when you eat — matters far less than how much and what you eat. The obsession with meal frequency, fasting windows, and eating every 2–3 hours has outrun the evidence."),
    GuideSection(heading: "Intermittent fasting: what it is and what it does", body: "Intermittent fasting (IF) is any eating pattern that involves regular periods of not eating. Common versions:\n\n• 16:8 — eat within an 8-hour window, fast for 16 hours\n• 5:2 — eat normally for 5 days, restrict to ~500 kcal for 2 days\n• OMAD — one meal a day\n\nIF works for fat loss. The reason it works is not metabolic magic — it's that fasting windows reduce the opportunity to eat, making it easier to maintain a calorie deficit."),
    GuideSection(heading: "IF vs regular meal spacing: what does the research say?", body: "When calories and protein are matched, intermittent fasting produces similar fat loss outcomes to regular eating patterns. The advantage of IF is adherence — some people simply find it easier to skip breakfast than to count calories all day.\n\nThe disadvantage: compressing all eating into a shorter window makes it harder to hit high protein targets and may reduce training performance if sessions are in the morning."),
    GuideSection(heading: "Meal frequency", body: "The idea that you need to eat every 2–3 hours to 'keep metabolism high' or 'prevent muscle breakdown' is not well supported. The metabolic boost from eating (thermic effect) is proportional to the total amount eaten, not how often.\n\nMuscle protein synthesis is influenced by total daily protein, not meal frequency — provided you're eating 1.6g/kg+.\n\nFor practical purposes: 3–5 meals per day works for most people. Eat when it fits your schedule and helps you control hunger."),
    GuideSection(heading: "The post-workout window", body: "The 'anabolic window' — the idea that you must eat protein within 30 minutes of finishing your workout — is heavily overstated.\n\nFor most people training in a fed state, consuming protein within 2–3 hours before or after training is sufficient. The window is far wider than the supplement industry suggests.\n\nIf you train fasted, eat a protein-containing meal soon after. Otherwise, the timing is a detail — total intake is what matters."),
    GuideSection(heading: "What does matter with timing", body: "The things that genuinely interact with timing:\n\n• Caffeine: stop 8–13 hours before bed (see Supplements article)\n• Large meals before bed: can reduce sleep quality for some people\n• Pre-workout carbs: useful for performance in morning training, not necessary otherwise\n• Training in a large deficit: can reduce performance — a small meal beforehand helps\n\nBeyond these specifics, meal timing is a preference, not a protocol."),
]

// MARK: - Guide Part View

struct GuidePartView: View {
    let part: GuidePart

    var body: some View {
        List {
            ForEach(part.sections) { section in
                VStack(alignment: .leading, spacing: 8) {
                    if let heading = section.heading {
                        Text(heading)
                            .font(.subheadline.weight(.semibold))
                    }
                    Text(section.body)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle(part.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Interactive Simplified Macro Rules (Part 5)

struct SimplifiedMacroRulesView: View {
    var body: some View {
        List {
            Section {
                Text("These simplified rules make tracking easier. Some accuracy is sacrificed for consistency — and consistency beats perfection every time. All values are based on raw/uncooked food.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            NavigationLink("Calorie Range") { CalorieRangeView() }
            NavigationLink("Lean Protein Estimator") { LeanProteinEstimatorView() }
            NavigationLink("Fruit Carb Estimator") { FruitCarbEstimatorView() }
            NavigationLink("Vegetables Guide") { VegetablesGuideView() }
            NavigationLink("Condiments Guide") { CondimentsGuideView() }

            Section("Cooking Spray Rule") {
                Text("1 spray = 1g of fat. If you spray 4 times, track 4g of fat.")
                    .font(.subheadline)
            }

            Section("Tracking Priority") {
                VStack(alignment: .leading, spacing: 6) {
                    PriorityRow(number: "1", label: "Hit your total calories")
                    PriorityRow(number: "2", label: "Hit your protein target")
                    PriorityRow(number: "3", label: "Fill remaining calories with carbs or fat — your preference")
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Simplified Macro Rules")
    }
}

private struct PriorityRow: View {
    let number: String
    let label: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.accentColor)
                .clipShape(Circle())
            Text(label)
                .font(.subheadline)
        }
    }
}

// MARK: - Calorie Range

struct CalorieRangeView: View {
    @State private var target: String = ""

    var targetNum: Int { Int(target) ?? 0 }
    var low: Int { max(0, targetNum - 100) }
    var high: Int { targetNum + 100 }

    var body: some View {
        Form {
            Section("Your target calories") {
                TextField("e.g. 2000", text: $target)
                    .keyboardType(.numberPad)
            }
            if targetNum > 0 {
                Section("Your daily range") {
                    LabeledContent("Low", value: "\(low) kcal")
                    LabeledContent("Target", value: "\(targetNum) kcal")
                    LabeledContent("High", value: "\(high) kcal")
                    Text("As long as you're within \(low)–\(high) kcal each day you'll make progress. Don't stress about hitting the exact number.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Calorie Range")
    }
}

// MARK: - Lean Protein Estimator

private let leanProteinSources: [(name: String, cal: Int, protein: Int)] = [
    ("Chicken Breast", 106, 24),
    ("Turkey Breast", 136, 31),
    ("Tuna", 99, 24),
    ("Tilapia / White Fish", 96, 20),
    ("Halibut", 107, 20),
    ("Pork Tenderloin", 143, 26),
    ("5% Fat Minced Beef", 136, 21),
    ("Lean Beef", 150, 25),
    ("Shrimp / Prawn", 85, 20),
    ("Whey Protein (1 scoop ~30g)", 120, 24),
]

struct LeanProteinEstimatorView: View {
    @State private var weight: String = "100"

    var weightNum: Double { Double(weight) ?? 0 }
    var protein: Double { weightNum / 100 * 25 }
    var calories: Double { weightNum / 100 * 100 }

    var body: some View {
        Form {
            Section("Simplified rule") {
                Text("100g of any lean protein source ≈ 25g protein, 100 kcal.\n\nThis ignores fat calories so it under-counts slightly, but it's consistent and fast.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("Estimate") {
                LabeledContent("Weight (g, raw)") {
                    TextField("100", text: $weight)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Protein", value: String(format: "~%.0f g", protein))
                LabeledContent("Calories (approx)", value: String(format: "~%.0f kcal", calories))
            }

            Section("Common lean sources (per 100g raw)") {
                ForEach(leanProteinSources, id: \.name) { source in
                    HStack {
                        Text(source.name)
                            .font(.subheadline)
                        Spacer()
                        Text("\(source.protein)g protein · \(source.cal) kcal")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Lean Protein Estimator")
    }
}

// MARK: - Fruit Carb Estimator

private let fruitTable: [(name: String, cal: Int, carbs: Int)] = [
    ("Apple", 95, 25),
    ("Banana", 105, 27),
    ("Pear", 58, 15),
    ("Orange", 47, 12),
    ("Grapes (1 cup)", 70, 18),
    ("Strawberries (1 cup)", 32, 8),
    ("Blueberries (1 cup)", 57, 15),
]

struct FruitCarbEstimatorView: View {
    @State private var pieces: String = "1"

    var piecesNum: Double { Double(pieces) ?? 0 }
    var carbs: Double { piecesNum * 20 }
    var calories: Double { piecesNum * 80 }

    var body: some View {
        Form {
            Section("Simplified rule") {
                Text("1 medium piece of fruit (or 1 cup of small fruit) ≈ 20g carbs, 80 kcal.\n\nTip: create a 'Custom Fruit' entry in your tracking app with these values so you never have to search for individual fruits again.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("Estimate") {
                LabeledContent("Pieces / cups") {
                    TextField("1", text: $pieces)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Carbs", value: String(format: "~%.0f g", carbs))
                LabeledContent("Calories (approx)", value: String(format: "~%.0f kcal", calories))
            }

            Section("Reference (per medium serving)") {
                ForEach(fruitTable, id: \.name) { f in
                    HStack {
                        Text(f.name)
                            .font(.subheadline)
                        Spacer()
                        Text("\(f.carbs)g carbs · \(f.cal) kcal")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Fruit Carb Estimator")
    }
}

// MARK: - Vegetables Guide

struct VegetablesGuideView: View {
    private let fibrous = ["Broccoli", "Asparagus", "Cauliflower", "Fresh Green Beans", "Celery", "Spinach", "Kale", "Okra", "Cucumbers", "Cabbage"]
    private let starchy = ["Potatoes", "Sweet Potato", "Carrots", "Sweet Corn", "Green Peas", "Beets"]

    var body: some View {
        List {
            Section {
                Text("Fibrous (non-starchy) vegetables are so low in calories and high in indigestible fibre that you don't need to track them. Eat as much as you want.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } header: {
                Label("Don't track these", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }

            ForEach(fibrous, id: \.self) { v in
                Text(v).font(.subheadline)
            }

            Section {
                Text("Starchy vegetables are higher in calories and digestible carbohydrates. Track these in your app.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } header: {
                Label("Track these", systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
            }

            ForEach(starchy, id: \.self) { v in
                Text(v).font(.subheadline)
            }
        }
        .navigationTitle("Vegetables Guide")
    }
}

// MARK: - Condiments Guide

struct CondimentsGuideView: View {
    private let dontTrack = ["Mustard", "Relish", "Soy Sauce", "Salsa", "Tabasco", "Sriracha"]
    private let doTrack = ["Ketchup", "BBQ Sauce", "Mayonnaise", "Honey", "Ranch / Creamy dressings", "Olive oil / other oils"]

    var body: some View {
        List {
            Section {
                Text("These condiments are so low in calories you can skip tracking them.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } header: {
                Label("Don't bother tracking", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            ForEach(dontTrack, id: \.self) { c in Text(c).font(.subheadline) }

            Section {
                Text("These add meaningful calories. Track them.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } header: {
                Label("Track these", systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
            }
            ForEach(doTrack, id: \.self) { c in Text(c).font(.subheadline) }
        }
        .navigationTitle("Condiments Guide")
    }
}
