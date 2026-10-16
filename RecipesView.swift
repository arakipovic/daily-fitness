import SwiftUI

// MARK: - Data

enum RecipeCategory: String, CaseIterable, Identifiable {
    case breakfast = "Breakfast"
    case lunchDinner = "Lunch / Dinner"
    var id: String { rawValue }
}

struct MacroVariant: Identifiable {
    let id = UUID()
    let label: String?
    let calories: Int
    let protein: Double
    let carbs: Double
    let fat: Double

    func scaled(by servings: Double) -> MacroVariant {
        MacroVariant(
            label: label,
            calories: Int((Double(calories) * servings).rounded()),
            protein: protein * servings,
            carbs: carbs * servings,
            fat: fat * servings
        )
    }
}

struct Recipe: Identifiable {
    let id = UUID()
    let name: String
    let category: RecipeCategory
    let servingNote: String?
    let extraNote: String?
    let ingredients: [String]
    let directions: [String]
    let macros: [MacroVariant]
}

let allRecipes: [Recipe] = [
    // MARK: Breakfast
    Recipe(
        name: "Turkey Wraps",
        category: .breakfast,
        servingNote: "Makes 4 wraps",
        extraNote: "Can also be eaten as a high-protein snack.",
        ingredients: [
            "4 turkey breast slices",
            "4 light cheese slices (e.g. Leerdammer)",
            "Spinach or lettuce",
            "Optional: cherry tomatoes, cucumbers, onions",
        ],
        directions: [
            "Lay out a turkey slice, add a cheese slice and spinach/lettuce.",
            "Add any optional veggies.",
            "Roll up and eat.",
        ],
        macros: [
            MacroVariant(label: nil, calories: 296, protein: 42, carbs: 0, fat: 13),
        ]
    ),
    Recipe(
        name: "High-Protein Yoghurt",
        category: .breakfast,
        servingNote: nil,
        extraNote: nil,
        ingredients: [
            "150g 0% fat Greek yoghurt (Fage recommended)",
            "1 scoop protein powder",
            "30–50g frozen berries of your choice",
            "Optional: a little honey",
        ],
        directions: [
            "Mix the yoghurt and protein powder together until smooth.",
            "Top with frozen berries.",
            "Add a drizzle of honey if desired.",
        ],
        macros: [
            MacroVariant(label: nil, calories: 198, protein: 40, carbs: 8, fat: 1.1),
        ]
    ),
    Recipe(
        name: "Cheesy Egg Scramble",
        category: .breakfast,
        servingNote: "Makes 1 serving",
        extraNote: nil,
        ingredients: [
            "2 whole eggs (or 1 whole egg + 200ml egg whites)",
            "100ml egg whites",
            "1 medium tomato, chopped",
            "2 medium mushrooms, chopped",
            "20g low-fat grated cheese (30% less fat)",
            "Spraying oil",
            "Salt, pepper, paprika to taste",
        ],
        directions: [
            "Crack eggs into a bowl, add egg whites, cheese, salt, pepper, and paprika. Mix and set aside.",
            "Chop the tomato and mushrooms.",
            "Heat pan over medium heat and spray with cooking oil.",
            "Add the chopped vegetables and cook for about 3 minutes.",
            "Pour in the egg mixture and cook for about 5 minutes until set.",
            "Serve and enjoy.",
        ],
        macros: [
            MacroVariant(label: "2 whole eggs + 100ml egg whites", calories: 258, protein: 28, carbs: 6, fat: 14),
            MacroVariant(label: "1 whole egg + 200ml egg whites", calories: 233, protein: 33, carbs: 7, fat: 12),
        ]
    ),
    Recipe(
        name: "Egg and Turkey Veggie Scramble",
        category: .breakfast,
        servingNote: nil,
        extraNote: nil,
        ingredients: [
            "2 whole eggs",
            "100ml egg whites",
            "50g mushrooms, chopped",
            "50g tomatoes, chopped",
            "50g turkey breast slices",
            "1 tbsp olive oil or zero-calorie cooking spray",
        ],
        directions: [
            "Chop the mushrooms and tomatoes.",
            "Whisk the whole eggs and egg whites together.",
            "Heat pan and add oil.",
            "Once hot, add all the vegetables and cook for about 5 minutes.",
            "Add the turkey slices, then pour in the eggs.",
            "Cook for 5 minutes, stirring occasionally.",
            "Serve and enjoy.",
        ],
        macros: [
            MacroVariant(label: nil, calories: 263, protein: 35, carbs: 5, fat: 12),
        ]
    ),
    Recipe(
        name: "ProYo",
        category: .breakfast,
        servingNote: nil,
        extraNote: nil,
        ingredients: [
            "150g frozen fruit (blueberries work well)",
            "50g 0% fat Greek yoghurt",
            "1 scoop protein powder (strawberry or banana)",
            "100–150ml water (adjust for consistency)",
            "Ice cubes",
        ],
        directions: [
            "Throw all ingredients into a blender.",
            "Blend until smooth.",
            "Adjust water for your preferred consistency and enjoy.",
        ],
        macros: [
            MacroVariant(label: nil, calories: 210, protein: 30, carbs: 18, fat: 2.4),
        ]
    ),
    Recipe(
        name: "Blueberry Pancake Proatmeal",
        category: .breakfast,
        servingNote: nil,
        extraNote: nil,
        ingredients: [
            "50g frozen blueberries",
            "60g old-fashioned oats",
            "250ml water",
            "1 serving vanilla or multi-purpose protein powder",
            "Pinch of salt",
            "Maple syrup to taste (Walden Farms for zero calories)",
        ],
        directions: [
            "Heat the blueberries, water, and salt in a pot until boiling.",
            "Add the oats, reduce heat, and simmer until your desired consistency (longer = thicker).",
            "Remove from heat, transfer to a bowl, and let cool.",
            "Once cooled, slowly mix in the protein powder. (Adding protein while too hot ruins the texture.)",
            "Sweeten with maple syrup to taste.",
        ],
        macros: [
            MacroVariant(label: nil, calories: 295, protein: 32, carbs: 38, fat: 4),
        ]
    ),
    Recipe(
        name: "Mango and Cream Overnight Oats",
        category: .breakfast,
        servingNote: nil,
        extraNote: nil,
        ingredients: [
            "50g old-fashioned oats",
            "125ml milk (cow, almond, or other)",
            "60ml pasteurised egg whites",
            "2–3 pieces dried mango, chopped",
            "1 serving vanilla protein powder",
        ],
        directions: [
            "Mix the egg whites, milk, and protein powder until well combined.",
            "Combine the mixture with the oats and dried mango in a bowl. (It will seem very liquidy — that's normal.)",
            "Cover and refrigerate overnight (about 8 hours) until oats reach your desired consistency.",
            "Enjoy cold.",
        ],
        macros: [
            MacroVariant(label: nil, calories: 394, protein: 42, carbs: 51, fat: 4),
        ]
    ),

    // MARK: Lunch / Dinner
    Recipe(
        name: "Oven-Baked Salmon with Baby Potatoes",
        category: .lunchDinner,
        servingNote: "Makes 1 serving",
        extraNote: nil,
        ingredients: [
            "120g salmon",
            "100g baby potatoes",
            "1 lemon, sliced",
            "Salt and pepper",
            "Optional: a little olive oil",
        ],
        directions: [
            "Preheat oven to 200°C (370°F).",
            "Put the potatoes into boiling water while the oven heats.",
            "Line a baking tray with foil. Place 3 thin lemon slices on the foil, then lay the salmon on top.",
            "Season with salt, pepper, and a drizzle of olive oil if using. Wrap the foil around the salmon.",
            "Bake for about 20 minutes until the salmon flakes easily.",
            "Drain the potatoes and serve everything together.",
        ],
        macros: [
            MacroVariant(label: nil, calories: 346, protein: 27, carbs: 16, fat: 19),
        ]
    ),
    Recipe(
        name: "Chilli",
        category: .lunchDinner,
        servingNote: "Makes 4 servings",
        extraNote: "Top with 0% Greek yoghurt if you wish.",
        ingredients: [
            "500g 5% fat minced beef",
            "1 tbsp olive oil",
            "1 green pepper, chopped",
            "1 red onion, chopped",
            "10g chopped garlic",
            "Chilli seasoning mix",
            "500g chopped tomatoes",
            "10g tomato purée",
            "500ml beef stock",
            "250g red kidney beans, drained",
        ],
        directions: [
            "Heat a large pan over medium heat. Add oil, onion, garlic, and pepper. Cook until the onion becomes translucent.",
            "Add the mince, break it up, and cook until browned (5–10 minutes).",
            "Add all remaining ingredients, reduce heat, and simmer for 30–40 minutes until the sauce has thickened.",
        ],
        macros: [
            MacroVariant(label: "Per serving", calories: 300, protein: 45, carbs: 15, fat: 7),
        ]
    ),
    Recipe(
        name: "Chicken Chipotle Soup",
        category: .lunchDinner,
        servingNote: "Makes 3 servings",
        extraNote: "Can also be made in a slow cooker or Instant Pot.",
        ingredients: [
            "400g diced chicken breast",
            "1 tsp chipotle cooking paste",
            "½ medium red onion, chopped",
            "1 tsp chopped garlic",
            "1 can sweet corn",
            "1 chicken stock cube dissolved in 2 cups water",
            "1 can chopped tomatoes",
            "1 can red kidney beans",
            "Salt, pepper, chilli powder, cumin to taste",
        ],
        directions: [
            "Fry the onion and garlic until translucent (about 3 minutes).",
            "Add all remaining ingredients to the pan.",
            "Cook on medium heat for 30–40 minutes, stirring every 10–15 minutes.",
        ],
        macros: [
            MacroVariant(label: "Per serving", calories: 326, protein: 45, carbs: 25, fat: 5),
        ]
    ),
    Recipe(
        name: "Chicken Vegetable Soup",
        category: .lunchDinner,
        servingNote: "Makes 2 servings",
        extraNote: nil,
        ingredients: [
            "500g chicken breast",
            "1 tbsp extra virgin olive oil",
            "250g white potatoes, cubed",
            "4 stock cubes",
            "500g frozen mixed vegetables",
            "Mixed herbs (thyme, basil, oregano)",
        ],
        directions: [
            "Sauté onions and garlic in olive oil for 5 minutes.",
            "Add chicken breast, broth, and potatoes. Bring to a boil.",
            "Reduce heat to medium-low, add frozen vegetables, and cook for 30 minutes.",
            "Use two forks to shred the chicken.",
            "Serve and enjoy.",
        ],
        macros: [
            MacroVariant(label: "Per serving", calories: 369, protein: 55, carbs: 13, fat: 9),
        ]
    ),
    Recipe(
        name: "Chicken Sausage and Mash",
        category: .lunchDinner,
        servingNote: "Makes 3 servings",
        extraNote: "Add a tbsp of Greek yoghurt to the mash for a creamier result.",
        ingredients: [
            "10 chicken sausages (e.g. Heck brand)",
            "200g cauliflower",
            "100g white potato",
            "50g peas",
            "Gravy granules (optional)",
        ],
        directions: [
            "Preheat oven to 180°C. Line a baking tray with foil.",
            "Place sausages in the tray and bake for 20 minutes, turning halfway.",
            "While sausages cook, boil the potatoes and cauliflower in separate pots until soft.",
            "Drain and mash the potatoes and cauliflower together. Add a tbsp of Greek yoghurt if desired.",
            "Serve the sausages with mash, peas, and gravy if using.",
        ],
        macros: [
            MacroVariant(label: "Per serving", calories: 342, protein: 39, carbs: 43, fat: 3.5),
        ]
    ),
    Recipe(
        name: "Prawn Stir-Fry",
        category: .lunchDinner,
        servingNote: "Makes 2 servings",
        extraNote: nil,
        ingredients: [
            "150g prawns",
            "Broccoli florets",
            "Mangetout (snow peas)",
            "Aubergine (eggplant), chopped",
            "Baby corn",
            "Spring onions, chopped",
            "Chow mein stir-fry sauce packet",
            "Zero-calorie cooking spray",
        ],
        directions: [
            "Spray pan with zero-cal spray and heat over medium-high heat.",
            "Chop all vegetables and add to the pan. Cook for about 5 minutes.",
            "Add the chow mein sauce and stir through.",
            "Add the prawns and cook for 2–3 minutes, stirring frequently.",
        ],
        macros: [
            MacroVariant(label: "Per serving", calories: 115, protein: 13, carbs: 14, fat: 1),
        ]
    ),
    Recipe(
        name: "Huevos Rancheros",
        category: .lunchDinner,
        servingNote: "Makes 2 servings",
        extraNote: nil,
        ingredients: [
            "1 can (400g) chopped tomatoes",
            "1 can (400g) red kidney beans",
            "1 spring onion, chopped",
            "Low-fat grated cheese (30% less fat)",
            "2 eggs",
            "Chopped red chillies to taste",
            "Chopped garlic to taste",
            "1–2 tsp cumin",
            "Jalapeños (optional)",
            "Handful of spinach",
            "Zero-calorie cooking spray",
        ],
        directions: [
            "Spray pan with zero-cal spray and heat.",
            "Add spring onion and cook for a few minutes.",
            "Stir in chillies, garlic, cumin, and jalapeños.",
            "Add the kidney beans, chopped tomatoes, and spinach. Stir everything together.",
            "Turn heat to low. Crack both eggs directly onto the mixture.",
            "Sprinkle cheese on top and cover the pan.",
            "Cook until the eggs are set and cheese is melted.",
        ],
        macros: [
            MacroVariant(label: "Per serving", calories: 406, protein: 32, carbs: 23, fat: 17),
        ]
    ),
    Recipe(
        name: "Portobello Burgers",
        category: .lunchDinner,
        servingNote: "Makes 2 burgers",
        extraNote: nil,
        ingredients: [
            "2 lean beef patties",
            "2 portobello mushrooms",
            "½ red onion, sliced",
            "1 tomato, sliced",
            "Optional: lettuce",
            "1 tbsp olive oil or zero-cal cooking spray",
        ],
        directions: [
            "Heat oil or spray in a pan over medium-high heat.",
            "Cook beef patties for about 5 minutes per side.",
            "Drizzle the portobello mushrooms with a little olive oil, place on a baking tray, and bake at 200°C for 10 minutes (flip after 5).",
            "Assemble: place a patty on top of a portobello mushroom. Top with sliced onion, tomato, and lettuce.",
        ],
        macros: [
            MacroVariant(label: "Per burger", calories: 162, protein: 27, carbs: 0, fat: 7.2),
        ]
    ),
    Recipe(
        name: "Tacos",
        category: .lunchDinner,
        servingNote: "Makes 4 servings",
        extraNote: nil,
        ingredients: [
            "500g 5% fat minced beef",
            "Small soft flour tortilla wraps",
            "1 tbsp olive oil",
            "½ red onion, chopped",
            "2–3 cherry tomatoes, chopped",
            "Handful of spinach or lettuce, chopped",
            "0% fat Greek yoghurt",
            "Salsa",
            "Taco seasoning mix",
            "50% less fat grated cheese",
        ],
        directions: [
            "Heat oil in a pan. Add mince and fry until browned.",
            "Add taco seasoning mix and 100ml of water. Stir and cook for 5 minutes.",
            "Fill each tortilla with mince, spinach, and cherry tomatoes.",
            "Top with salsa, Greek yoghurt, and cheese.",
        ],
        macros: [
            MacroVariant(label: "Per serving", calories: 377, protein: 43, carbs: 22, fat: 13),
        ]
    ),
    Recipe(
        name: "One-Pan Chicken Sausage and Veg",
        category: .lunchDinner,
        servingNote: "Makes 2–3 servings",
        extraNote: nil,
        ingredients: [
            "10 chicken sausages (e.g. Heck brand)",
            "1 courgette, chopped",
            "1 pepper, chopped",
            "1 red onion, chopped",
            "Any additional vegetables you like",
            "Salt, pepper, mixed herbs to taste",
            "Zero-cal cooking spray or 1 tbsp olive oil",
        ],
        directions: [
            "Spray or oil a pan and heat over medium-high.",
            "Chop the sausages into bite-sized pieces and fry.",
            "Add all the chopped vegetables.",
            "Season with salt, pepper, and mixed herbs.",
            "Cook for 10–15 minutes until sausages are cooked through.",
        ],
        macros: [
            MacroVariant(label: "Per serving", calories: 198, protein: 39, carbs: 3.2, fat: 3.6),
        ]
    ),
    Recipe(
        name: "Chicken Tray Bake",
        category: .lunchDinner,
        servingNote: "Makes 3 servings",
        extraNote: nil,
        ingredients: [
            "500g chicken breast, diced",
            "1 tbsp olive oil",
            "1 red pepper, chopped",
            "1 green pepper, chopped",
            "1 yellow pepper, chopped",
            "1 red onion, chopped",
            "200g cherry tomatoes, halved",
            "2 tbsp balsamic vinegar",
            "1 tsp smoked paprika",
            "2 tsp oregano",
            "2 tsp chopped garlic",
            "½ tsp salt",
            "Lemon slices",
            "Optional: pitted black olives",
        ],
        directions: [
            "Preheat oven to 180°C.",
            "Mix the marinade: olive oil, balsamic vinegar, paprika, oregano, garlic, and salt in a small bowl.",
            "Place chicken, peppers, tomatoes, and onion on a baking tray.",
            "Pour the marinade over everything and toss to coat.",
            "Bake for 25 minutes.",
            "Add lemon slices and olives, then return to oven for 5–10 more minutes.",
        ],
        macros: [
            MacroVariant(label: "Per serving", calories: 360, protein: 43, carbs: 0, fat: 14),
        ]
    ),
    Recipe(
        name: "\"Meatza\" and Sweet Potato Fries",
        category: .lunchDinner,
        servingNote: "Makes 4 servings",
        extraNote: nil,
        ingredients: [
            "500g 5% fat minced beef",
            "1 green pepper, chopped",
            "1 red pepper, chopped",
            "1 medium red onion, chopped",
            "30g 50% less fat cheese",
            "50g turkey breast slices",
            "2 tbsp tomato purée",
            "1 tbsp mixed herbs",
            "300g sweet potato",
            "1 tbsp olive oil",
            "Salt, pepper, paprika",
        ],
        directions: [
            "Preheat oven to 230°C.",
            "Press the mince into a flat layer (no thicker than 2cm) on a foil-lined baking tray. Bake for 15 minutes.",
            "Meanwhile, spray a frying pan with zero-cal spray and cook the onion, peppers, and turkey for 5–10 minutes.",
            "Remove the meat base and spread tomato purée over it like a pizza sauce.",
            "Top with the onion/pepper/turkey mixture, then sprinkle cheese on top.",
            "Return to oven for 5 minutes until cheese melts.",
            "For the fries: preheat oven to 220°C. Peel and cut sweet potatoes into wedges.",
            "Toss with olive oil, salt, pepper, and paprika. Spread on a baking tray.",
            "Bake for 18–24 minutes, turning occasionally, until golden. Rest 5 minutes before serving.",
        ],
        macros: [
            MacroVariant(label: "Meatza + fries", calories: 371, protein: 46, carbs: 31, fat: 14),
            MacroVariant(label: "Meatza only", calories: 247, protein: 45, carbs: 0, fat: 14),
        ]
    ),
    Recipe(
        name: "Mexican Chicken and Rice",
        category: .lunchDinner,
        servingNote: "Makes 3 servings",
        extraNote: "Can use frying steak instead of chicken.",
        ingredients: [
            "400g chicken breast (or frying steak)",
            "1 tbsp olive oil",
            "1 red pepper, chopped",
            "1 red onion, chopped",
            "2 tbsp fajita spice mix",
            "250g basmati rice (microwave packet is fine)",
            "1 tbsp tomato purée",
        ],
        directions: [
            "Heat olive oil in a pan.",
            "Add chicken (or steak) and cook until it starts to brown.",
            "Add the vegetables and continue cooking until the chicken is cooked through.",
            "Heat the rice in the microwave according to packet instructions.",
            "Add the fajita spice mix to the pan and stir through for a few minutes.",
            "Add the cooked rice and tomato purée. Mix everything together and cook for another few minutes.",
            "Serve.",
        ],
        macros: [
            MacroVariant(label: "Per serving", calories: 390, protein: 40, carbs: 25, fat: 12),
        ]
    ),

    // MARK: New high-protein simple recipes — Breakfast
    Recipe(
        name: "Cottage Cheese Bowl",
        category: .breakfast,
        servingNote: nil,
        extraNote: "No cooking required. Ready in 2 minutes.",
        ingredients: [
            "200g 0% fat cottage cheese",
            "100g frozen or fresh berries",
            "1 tsp honey (optional)",
        ],
        directions: [
            "Spoon cottage cheese into a bowl.",
            "Top with berries.",
            "Drizzle honey if desired and eat immediately.",
        ],
        macros: [
            MacroVariant(label: nil, calories: 225, protein: 26, carbs: 18, fat: 2),
        ]
    ),
    Recipe(
        name: "Egg White Omelette",
        category: .breakfast,
        servingNote: nil,
        extraNote: "Ready in 5 minutes.",
        ingredients: [
            "300ml liquid egg whites",
            "50g mushrooms, sliced",
            "½ red pepper, diced",
            "30g low-fat grated cheese (30% less fat)",
            "Salt, pepper, paprika",
            "Zero-calorie cooking spray",
        ],
        directions: [
            "Spray a non-stick pan and heat over medium.",
            "Cook mushrooms and pepper for 2–3 minutes.",
            "Pour egg whites over the veg, season, and cook until mostly set (~3 min).",
            "Sprinkle cheese over one half, fold and serve.",
        ],
        macros: [
            MacroVariant(label: nil, calories: 190, protein: 35, carbs: 5, fat: 3),
        ]
    ),
    Recipe(
        name: "Cottage Cheese Pancakes",
        category: .breakfast,
        servingNote: "Makes 2 servings",
        extraNote: nil,
        ingredients: [
            "250g 0% fat cottage cheese",
            "3 whole eggs",
            "40g old-fashioned oats",
            "½ tsp baking powder",
            "Pinch of salt",
            "Zero-calorie cooking spray",
        ],
        directions: [
            "Blend all ingredients until smooth (or mix vigorously by hand for a chunkier texture).",
            "Spray a non-stick pan and heat over medium-low.",
            "Pour small ladles of batter, cook 2–3 minutes per side until golden.",
            "Serve with berries or a drizzle of maple syrup.",
        ],
        macros: [
            MacroVariant(label: "Per serving", calories: 265, protein: 24, carbs: 16, fat: 9),
        ]
    ),
    Recipe(
        name: "Protein Porridge",
        category: .breakfast,
        servingNote: nil,
        extraNote: nil,
        ingredients: [
            "60g old-fashioned oats",
            "350ml water (or milk for creamier result)",
            "1 scoop vanilla protein powder",
            "1 small banana, sliced",
            "Pinch of salt",
            "Cinnamon to taste",
        ],
        directions: [
            "Bring water to a boil, add salt and oats. Simmer 5 minutes, stirring occasionally.",
            "Remove from heat and let cool 2 minutes.",
            "Stir in protein powder until smooth. (Don't add protein while boiling — it turns rubbery.)",
            "Top with banana and cinnamon.",
        ],
        macros: [
            MacroVariant(label: nil, calories: 390, protein: 36, carbs: 52, fat: 5),
        ]
    ),

    // MARK: New high-protein simple recipes — Lunch / Dinner
    Recipe(
        name: "Baked Chicken Breast",
        category: .lunchDinner,
        servingNote: "Makes 1 serving",
        extraNote: "As simple as it gets. Pair with any carb source and veg.",
        ingredients: [
            "200g chicken breast",
            "1 tsp olive oil",
            "Salt, pepper, garlic powder, paprika",
            "Lemon juice (optional)",
        ],
        directions: [
            "Preheat oven to 200°C.",
            "Pat chicken dry. Rub with olive oil and season generously.",
            "Place on a lined baking tray.",
            "Bake 20–25 minutes until cooked through (internal temp 74°C).",
            "Rest 5 minutes before cutting.",
        ],
        macros: [
            MacroVariant(label: nil, calories: 230, protein: 44, carbs: 0, fat: 6),
        ]
    ),
    Recipe(
        name: "Tuna Salad Plate",
        category: .lunchDinner,
        servingNote: nil,
        extraNote: "No cooking. Ready in 5 minutes.",
        ingredients: [
            "2 cans (120g each drained) tuna in water",
            "50g 0% Greek yoghurt",
            "1 tsp Dijon mustard",
            "Cucumber, celery, or spring onion, chopped",
            "4 rice cakes",
            "Salt, pepper, lemon juice",
        ],
        directions: [
            "Drain the tuna thoroughly.",
            "Mix tuna with Greek yoghurt, mustard, chopped veg, lemon juice, salt, and pepper.",
            "Serve on rice cakes.",
        ],
        macros: [
            MacroVariant(label: nil, calories: 310, protein: 52, carbs: 20, fat: 3),
        ]
    ),
    Recipe(
        name: "Tuna Pasta",
        category: .lunchDinner,
        servingNote: "Makes 2 servings",
        extraNote: nil,
        ingredients: [
            "2 cans (120g each drained) tuna in water",
            "150g dry pasta (penne or fusilli)",
            "200g passata or chopped tomatoes",
            "2 cloves garlic, minced",
            "½ tsp chilli flakes (optional)",
            "Salt, pepper, mixed herbs",
            "Zero-calorie cooking spray",
        ],
        directions: [
            "Cook pasta according to packet instructions. Drain and reserve a cup of pasta water.",
            "Spray pan and cook garlic with chilli flakes for 1 minute.",
            "Add passata and herbs, simmer 5 minutes.",
            "Flake in tuna, stir through. Add a splash of pasta water if too thick.",
            "Toss with pasta and serve.",
        ],
        macros: [
            MacroVariant(label: "Per serving", calories: 390, protein: 38, carbs: 52, fat: 3),
        ]
    ),
    Recipe(
        name: "Turkey Mince Bowl",
        category: .lunchDinner,
        servingNote: "Makes 2 servings",
        extraNote: nil,
        ingredients: [
            "300g lean turkey mince (99% lean)",
            "250g microwave basmati rice",
            "100g salsa (shop-bought)",
            "50g 0% Greek yoghurt",
            "Taco or fajita seasoning",
            "Zero-calorie cooking spray",
        ],
        directions: [
            "Spray pan and brown turkey mince over medium-high heat, breaking it up.",
            "Add seasoning and 2–3 tbsp water. Stir and cook 2 more minutes.",
            "Microwave rice according to packet.",
            "Serve turkey over rice, top with salsa and Greek yoghurt.",
        ],
        macros: [
            MacroVariant(label: "Per serving", calories: 345, protein: 40, carbs: 40, fat: 3),
        ]
    ),
    Recipe(
        name: "Baked Cod and Broccoli",
        category: .lunchDinner,
        servingNote: "Makes 1 serving",
        extraNote: nil,
        ingredients: [
            "200g cod fillet (or other white fish)",
            "200g broccoli florets",
            "½ lemon, sliced",
            "1 tsp olive oil",
            "Salt, pepper, garlic powder, paprika",
        ],
        directions: [
            "Preheat oven to 200°C.",
            "Toss broccoli with olive oil, salt, and pepper. Spread on a baking tray.",
            "Place cod on the same tray. Season fish and lay lemon slices on top.",
            "Bake 18–22 minutes until fish flakes and broccoli is tender with some char.",
        ],
        macros: [
            MacroVariant(label: nil, calories: 205, protein: 40, carbs: 8, fat: 3),
        ]
    ),
    Recipe(
        name: "Prawn and Egg Fried Rice",
        category: .lunchDinner,
        servingNote: "Makes 2 servings",
        extraNote: "Use day-old rice if possible — it fries better.",
        ingredients: [
            "200g cooked prawns",
            "3 whole eggs",
            "250g microwave basmati rice",
            "100g frozen peas",
            "3 spring onions, chopped",
            "2 tbsp low-sodium soy sauce",
            "1 tsp sesame oil (optional)",
            "Zero-calorie cooking spray",
        ],
        directions: [
            "Microwave the rice and let cool slightly.",
            "Scramble the eggs in a sprayed pan over high heat. Set aside.",
            "Add prawns, peas, and spring onion to the same pan and stir-fry 2 minutes.",
            "Add rice and toss everything together.",
            "Push to one side, return eggs to pan, mix through.",
            "Add soy sauce and sesame oil. Stir-fry another minute and serve.",
        ],
        macros: [
            MacroVariant(label: "Per serving", calories: 290, protein: 33, carbs: 28, fat: 7),
        ]
    ),
]

// MARK: - Views

struct RecipesView: View {
    var logDate: Date? = nil  // set when opened from food log for logging context

    @State private var searchText = ""
    @State private var selectedCategory: RecipeCategory? = nil

    var filtered: [Recipe] {
        allRecipes.filter { recipe in
            let matchesCategory = selectedCategory == nil || recipe.category == selectedCategory
            let matchesSearch = searchText.isEmpty || recipe.name.localizedCaseInsensitiveContains(searchText)
            return matchesCategory && matchesSearch
        }
    }

    var grouped: [(RecipeCategory, [Recipe])] {
        let cats: [RecipeCategory] = selectedCategory.map { [$0] } ?? RecipeCategory.allCases
        return cats.compactMap { cat in
            let recipes = filtered.filter { $0.category == cat }
            return recipes.isEmpty ? nil : (cat, recipes)
        }
    }

    var body: some View {
        List {
            Picker("Category", selection: $selectedCategory) {
                Text("All").tag(Optional<RecipeCategory>.none)
                ForEach(RecipeCategory.allCases) { cat in
                    Text(cat.rawValue).tag(Optional(cat))
                }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            .padding(.vertical, 4)

            ForEach(grouped, id: \.0) { category, recipes in
                Section(category.rawValue) {
                    ForEach(recipes) { recipe in
                        NavigationLink {
                            RecipeDetailView(recipe: recipe, logDate: logDate)
                        } label: {
                            RecipeRowView(recipe: recipe)
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search recipes")
        .navigationTitle("Recipes")
        .trackScreen("recipes")
    }
}

private struct RecipeRowView: View {
    let recipe: Recipe

    var primaryMacro: MacroVariant? { recipe.macros.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(recipe.name)
                .font(.subheadline.weight(.medium))
            if let m = primaryMacro {
                HStack(spacing: 12) {
                    MacroChip(label: "P", value: m.protein, color: .blue)
                    MacroChip(label: "C", value: m.carbs, color: .orange)
                    MacroChip(label: "F", value: m.fat, color: .yellow)
                    Spacer()
                    Text("\(m.calories) kcal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct RecipeDetailView: View {
    let recipe: Recipe
    var logDate: Date? = nil

    @State private var showingLogSheet = false

    var body: some View {
        List {
            if let note = recipe.extraNote {
                Section {
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .italic()
                }
            }

            if let servingNote = recipe.servingNote {
                Section {
                    Label(servingNote, systemImage: "person.2")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            // Macros
            Section("Macros") {
                ForEach(recipe.macros) { variant in
                    VStack(alignment: .leading, spacing: 8) {
                        if let label = variant.label {
                            Text(label)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 0) {
                            MacroBlock(label: "Calories", value: "\(variant.calories)", unit: "kcal", color: .primary)
                            MacroBlock(label: "Protein", value: String(format: "%.0f", variant.protein), unit: "g", color: .blue)
                            MacroBlock(label: "Carbs", value: String(format: "%.0f", variant.carbs), unit: "g", color: .orange)
                            MacroBlock(label: "Fat", value: String(format: "%.1f", variant.fat), unit: "g", color: .yellow)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            // Ingredients
            Section("Ingredients") {
                ForEach(recipe.ingredients, id: \.self) { ingredient in
                    Label(ingredient, systemImage: "circle.fill")
                        .font(.subheadline)
                        .labelStyle(BulletLabelStyle())
                }
            }

            // Directions
            Section("Directions") {
                ForEach(Array(recipe.directions.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(i + 1)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(Color.accentColor)
                            .clipShape(Circle())
                        Text(step)
                            .font(.subheadline)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle(recipe.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Log") { showingLogSheet = true }
                    .fontWeight(.semibold)
            }
        }
        .sheet(isPresented: $showingLogSheet) {
            RecipeLogSheet(recipe: recipe, date: logDate ?? Date())
        }
    }
}

// MARK: - Recipe Log Sheet

struct RecipeLogSheet: View {
    let recipe: Recipe
    let date: Date

    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var selectedVariantIndex = 0
    @State private var servings: Double = 1.0
    @State private var meal: MealType = MealType.guess(from: Date())

    private var selectedVariant: MacroVariant { recipe.macros[selectedVariantIndex] }
    private var scaled: MacroVariant { selectedVariant.scaled(by: servings) }

    private var servingsLabel: String {
        servings == servings.rounded() ? "\(Int(servings))" : String(format: "%.1f", servings)
    }

    var body: some View {
        NavigationStack {
            Form {
                if recipe.macros.count > 1 {
                    Section("Variant") {
                        Picker("Variant", selection: $selectedVariantIndex) {
                            ForEach(recipe.macros.indices, id: \.self) { i in
                                Text(recipe.macros[i].label ?? "Option \(i + 1)").tag(i)
                            }
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                        .padding(.vertical, 4)
                    }
                }

                Section {
                    Stepper(value: $servings, in: 0.5...20, step: 0.5) {
                        HStack {
                            Text("Servings")
                            Spacer()
                            Text(servingsLabel)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                        }
                    }
                    if let note = recipe.servingNote {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Macros") {
                    LabeledContent("Calories", value: "\(scaled.calories) kcal")
                    LabeledContent("Protein", value: "\(Int(scaled.protein.rounded()))g")
                    LabeledContent("Carbs", value: "\(Int(scaled.carbs.rounded()))g")
                    LabeledContent("Fat", value: String(format: "%.1fg", scaled.fat))
                }

                Section("Meal") {
                    Picker("Meal", selection: $meal) {
                        ForEach(MealType.allCases) { m in
                            Label(m.rawValue, systemImage: m.icon).tag(m)
                        }
                    }
                }
            }
            .navigationTitle("Log \(recipe.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") {
                        store.addFoodEntry(FoodEntry(
                            name: recipe.name,
                            calories: scaled.calories,
                            protein: scaled.protein,
                            carbs: scaled.carbs,
                            fat: scaled.fat,
                            date: date,
                            meal: meal
                        ))
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Helper Views

private struct MacroChip: View {
    let label: String
    let value: Double
    let color: Color

    var body: some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(color)
            Text(String(format: "%.0fg", value))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct MacroBlock: View {
    let label: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.weight(.semibold))
                .foregroundStyle(color == .primary ? Color.primary : color)
            Text(unit)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct BulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.system(size: 5))
                .foregroundStyle(.secondary)
                .padding(.top, 6)
            configuration.title
        }
    }
}
