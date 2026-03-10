import Foundation

extension WorkoutStore {

    // MARK: - Request AI analysis for a workout

    func requestAIAnalysis(workoutId: UUID, routineName: String, sets: [WorkoutSet]) async -> AIAnalysisResult? {
        // Check if analysis already exists
        if let existing: [WorkoutAnalysisRow] = await sb.tryGet(
            "workout_analyses?workout_id=eq.\(workoutId)&limit=1"
        ), let row = existing.first {
            return parseAnalysis(row.analysisJson)
        }

        // Fetch previous session data for this routine
        let previousSets = await fetchPreviousSessionSets(routineName: routineName, excludeWorkoutId: workoutId)

        // Fetch routine exercises for target rep ranges
        let routineExercises = await fetchRoutineExercises(routineName: routineName)

        // Build the prompt with full context
        let prompt = buildAnalysisPrompt(routineName: routineName, sets: sets, previousSets: previousSets, routineExercises: routineExercises)

        // Call Claude
        let systemPrompt = """
        You are an elite strength coach analyzing a client's workout. Be specific, cite numbers, and coach like you're being paid $500/hour. No generic praise — every observation must reference actual exercises and numbers.

        You MUST respond with ONLY valid JSON, no markdown, no code fences, no extra text.
        Use this exact JSON structure:
        {
          "summary": "2-3 sentences. Lead with the most important finding (PR, plateau, volume change). Reference specific exercises and numbers. End with one clear directive for next session.",
          "overall_rating": "excellent|good|average|needs_improvement",
          "volume_analysis": {
            "today_volume": 12500.0,
            "previous_volume": 12000.0,
            "change_pct": 4.2,
            "assessment": "1 sentence comparing today's volume to previous session with context"
          },
          "suggestions": [
            {
              "exercise_name": "Exercise Name",
              "action": "increase_weight|increase_reps|maintain|decrease_weight|add_drop_set",
              "current_weight": 60.0,
              "current_reps": 10,
              "suggested_weight": 62.5,
              "suggested_reps": 8,
              "drop_set_weight": null,
              "drop_set_reps": null,
              "reason": "Specific reason citing the data"
            }
          ],
          "next_session_targets": [
            {
              "exercise_name": "Exercise Name",
              "target_weight": 62.5,
              "target_reps": 10,
              "drop_set_weight": null,
              "drop_set_reps": null,
              "note": "What specifically to aim for and why"
            }
          ],
          "plateau_alerts": [
            {
              "exercise_name": "Exercise Name",
              "sessions_stalled": 2,
              "suggestion": "Specific technique to break through"
            }
          ],
          "strengths": ["Each strength MUST name a specific exercise and cite numbers, e.g. 'Ab Wheel Rollout up from 15 to 17 reps — solid core progression'"],
          "weaknesses": ["Each weakness MUST name a specific exercise and explain the issue, e.g. 'Incline DB Curl stalled at 10kg×10 for 2 sessions — needs rep or weight bump'"]
        }

        CRITICAL RULES — violating these makes the analysis useless:

        1. EVERY exercise must appear in suggestions AND next_session_targets. No exceptions. If a workout has 9 exercises, there must be 9 suggestions and 9 next_session_targets. A coach doesn't skip exercises.

        2. Weight increments are STRICT:
           - Cable/machine exercises: 5kg increments (cable stacks go 5kg at a time)
           - Barbell exercises: 2.5kg increments (upper body), 5kg (lower body)
           - Dumbbells: 2kg increments (dumbbells go 8→10→12→14)
           - NEVER suggest a jump larger than these minimums per session

        3. Progressive overload logic (follow this decision tree):
           a. If all sets hit the TOP of the target rep range → increase weight by the minimum increment
           b. If all sets hit the MIDDLE of the rep range → increase reps (aim for top of range next session)
           c. If sets are at BOTTOM of rep range → maintain weight, push for more reps. Do NOT increase weight.
           d. If reps DROPPED vs previous session at same weight → flag as concern, maintain or decrease
           e. If no previous data → maintain current weight/reps, mark as "baseline"

        4. Fatigue and rep pattern assessment:
           - 1 rep drop on the last set is NORMAL and expected (e.g. 12/12/11). Do NOT flag this as a weakness.
           - 2+ rep drop across sets IS a fatigue concern (e.g. 12/10/8). Flag this.
           - 0 rep drop across all sets at the same weight means the client probably has 1-2 reps in reserve — note they could push harder.
           - When the data shows [PATTERN: DESCENDING REPS], this is intentional fatigue — do NOT suggest maintaining the highest rep count. Base progression on set 1 performance.
           - When the data shows [PATTERN: DROP SET], acknowledge the drop set. Evaluate based on the top set only.
           - When the data shows [PATTERN: FAILURE], flag as a concern and suggest maintaining or decreasing weight.

        5. Volume analysis:
           - The prompt includes PRE-CALCULATED volume numbers. Use those EXACT values for today_volume, previous_volume, and change_pct. Do NOT recalculate — LLMs make arithmetic errors.
           - If the prompt says "Previous session total volume: no data", set previous_volume and change_pct to null.

        6. Plateau detection:
           - Flag in plateau_alerts if: same weight AND same reps as previous session (comparing best set or majority of sets)
           - Also flag if all sets are identical (e.g. 3×50kg×10) AND at the bottom of the target rep range — this means the client is stuck
           - For each plateau, suggest a SPECIFIC strategy: drop set on last set, pause reps (2-sec pause at bottom), add a 4th set at lower weight, switch grip variation, etc.
           - Set sessions_stalled to 2 if matching previous session, higher if you can infer from the data

        7. Drop set recommendations:
           - When action is "add_drop_set", also provide drop_set_weight (75% of working weight, rounded to nearest 2.5kg) and drop_set_reps (aim for same or slightly higher reps as the last working set).
           - Suggest drop sets when: client is plateaued for 2+ sessions, OR hitting top of rep range consistently and needs extra volume, OR as a finisher on isolation exercises.
           - In next_session_targets, include drop_set_weight and drop_set_reps when recommending a drop set.
           - Do NOT suggest drop sets on compound barbell movements (squats, deadlifts, bench press). Prefer them on cable/machine and isolation exercises.

        8. Strengths: 2-3 items. Each MUST cite exercise name + specific numbers.
        9. Weaknesses: 1-3 items. Each MUST cite exercise name + explain what's wrong with numbers.
        10. Rating: "excellent" = weight or rep PRs on multiple exercises. "good" = solid session, maintained or progressed on most. "average" = stalled on several exercises. "needs_improvement" = regression.
        """

        do {
            let response = try await ClaudeClient.shared.send(
                systemPrompt: systemPrompt,
                userMessage: prompt
            )

            guard let result = parseAnalysis(response) else {
                print("[AI] Failed to parse Claude response")
                return nil
            }

            // Store in Supabase
            let insert = WorkoutAnalysisInsert(
                workoutId: workoutId,
                routineName: routineName,
                analysisJson: response
            )
            do {
                try await sb.postBatch("workout_analyses", body: [insert])
            } catch {
                print("[AI] Failed to store analysis: \(error.localizedDescription)")
            }

            // Store suggestions
            await storeSuggestions(workoutId: workoutId, sets: sets, suggestions: result.suggestions)

            return result
        } catch {
            print("[AI] Claude API error: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Delete cached analysis (for re-trigger)

    func deleteAnalysisCache(workoutId: UUID) async {
        try? await sb.delete("workout_analyses?workout_id=eq.\(workoutId)")
        try? await sb.delete("ai_suggestions?workout_id=eq.\(workoutId)")
    }

    // MARK: - Delete cached session goals (for re-trigger)

    func deleteSessionGoalsCache(routineName: String) async {
        let today = isoDate(Date())
        let encoded = routineName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? routineName
        try? await sb.delete("session_goals?routine_name=eq.\(encoded)&goal_date=eq.\(today)")
    }

    // MARK: - Load existing analysis

    func loadExistingAnalysis(workoutId: UUID) async -> AIAnalysisResult? {
        guard let rows: [WorkoutAnalysisRow] = await sb.tryGet(
            "workout_analyses?workout_id=eq.\(workoutId)&limit=1"
        ), let row = rows.first else { return nil }
        return parseAnalysis(row.analysisJson)
    }

    // MARK: - Accept/Reject suggestion

    func updateSuggestionStatus(id: UUID, status: String) async {
        struct StatusPatch: Encodable { let status: String }
        do {
            try await sb.patch("ai_suggestions?id=eq.\(id)", body: StatusPatch(status: status))
        } catch {
            print("[AI] Failed to update suggestion: \(error.localizedDescription)")
        }
    }

    // MARK: - Load pending suggestions for a routine

    func loadPendingSuggestions(routineName: String) async -> [AISuggestionRow] {
        // Get the most recent workout with this routine that has AI suggestions
        guard let workouts: [Workout] = await sb.tryGet(
            "workouts?select=id&routine_name=eq.\(routineName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? routineName)" +
            "&finished_at=not.is.null&order=started_at.desc&limit=1"
        ), let lastWorkout = workouts.first else { return [] }

        return await sb.tryGet(
            "ai_suggestions?workout_id=eq.\(lastWorkout.id)&status=eq.pending&order=exercise_name"
        ) ?? []
    }

    // MARK: - Load accepted suggestions (goals) for a routine

    func loadAcceptedSuggestions(routineName: String) async -> [AISuggestionRow] {
        guard let workouts: [Workout] = await sb.tryGet(
            "workouts?select=id&routine_name=eq.\(routineName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? routineName)" +
            "&finished_at=not.is.null&order=started_at.desc&limit=1"
        ), let lastWorkout = workouts.first else { return [] }

        return await sb.tryGet(
            "ai_suggestions?workout_id=eq.\(lastWorkout.id)&status=eq.accepted&order=exercise_name"
        ) ?? []
    }

    // MARK: - Session goals (pre-workout AI)

    func generateSessionGoals(routineName: String, exercises: [RoutineExercise]) async -> SessionGoalsResult? {
        let today = isoDate(Date())
        let encoded = routineName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? routineName

        // Check cache — same routine + same day
        if let cached: [SessionGoalRow] = await sb.tryGet(
            "session_goals?routine_name=eq.\(encoded)&goal_date=eq.\(today)&limit=1"
        ), let row = cached.first {
            return parseSessionGoals(row.goalsJson)
        }

        // Fetch recent history for each exercise (last 4 sessions, across ALL routines)
        var historyLines: [String] = ["Routine: \(routineName)", ""]
        let exerciseNames = exercises.filter { !$0.isWarmup }.map { $0.exercises.name }

        for name in exerciseNames {
            let nameEnc = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
            let sets: [WorkoutSet] = await sb.tryGet(
                "workout_sets?exercise_name=eq.\(nameEnc)&order=logged_at.desc&limit=20"
            ) ?? []

            // Group by workout (date)
            let byWorkout = Dictionary(grouping: sets) { $0.workoutId }
            let sortedWorkouts = byWorkout.sorted {
                ($0.value.first?.loggedAt ?? .distantPast) > ($1.value.first?.loggedAt ?? .distantPast)
            }.prefix(4)

            let re = exercises.first { $0.exercises.name == name }
            let targetMin = re?.targetRepsMin ?? 0
            let targetMax = re?.targetRepsMax ?? 0
            let targetSets = re?.targetSets ?? 3
            let equipment = re?.exercises.equipment ?? "unknown"

            historyLines.append("\(name) (target: \(targetSets) sets × \(targetMin)–\(targetMax) reps, equipment: \(equipment)):")

            if sortedWorkouts.isEmpty {
                historyLines.append("  No previous data")
            } else {
                for (_, wkSets) in sortedWorkouts {
                    let sorted = wkSets.sorted { $0.setNumber < $1.setNumber }
                    let dateStr = isoDate(sorted.first?.loggedAt ?? Date())
                    let setsDesc = sorted.map { s in
                        let w = s.weightKg == 0 ? "BW" : "\(s.weightKg.clean)kg"
                        return "\(w)×\(s.reps)"
                    }.joined(separator: ", ")
                    historyLines.append("  \(dateStr): \(setsDesc)")
                }
            }
            historyLines.append("")
        }

        let userMessage = historyLines.joined(separator: "\n")

        let systemPrompt = """
        You are an elite strength coach planning today's session. Analyze the exercise history and give precise targets for every exercise. Be specific — cite actual numbers from previous sessions in your reasoning.

        You MUST respond with ONLY valid JSON, no markdown, no code fences, no extra text.
        Use this exact JSON structure:
        {
          "summary": "1-2 sentences. State the session focus and ONE key priority. If recent sessions show a pattern (deload recovery, plateau, strong progression), name it. Be direct.",
          "goals": [
            {
              "exercise_name": "Exercise Name",
              "action": "increase_weight|increase_reps|maintain|decrease_weight|deload|add_drop_set",
              "suggested_weight": 62.5,
              "suggested_reps": 8,
              "drop_set_weight": null,
              "drop_set_reps": null,
              "reasoning": "MUST cite specific numbers from history. E.g. 'Last 2 sessions: 80kg for 12/12/11 and 12/12/12 — consistently at top of 8-12 range, ready for 85kg'"
            }
          ]
        }

        CRITICAL RULES:

        1. ONE goal per exercise. Skip warm-up exercises only.

        2. Weight increments are STRICT:
           - Cable/machine exercises: 5kg increments
           - Barbell exercises: 2.5kg (upper body), 5kg (lower body)
           - Dumbbells: 2kg increments
           - NEVER exceed these in a single session

        3. Progressive overload decision tree (follow exactly):
           a. ALL sets at TOP of target rep range for 2+ sessions → increase_weight (minimum increment)
           b. ALL sets at TOP of target rep range for 1 session → increase_reps to verify consistency (suggest same weight, same reps — "confirm last session's performance before adding weight")
           c. Sets in MIDDLE of rep range → increase_reps (suggest current weight, +1-2 reps vs last session)
           d. Sets at BOTTOM of rep range → maintain (suggest same weight and reps, focus on hitting more reps)
           e. Reps DROPPING across recent sessions → maintain or decrease_weight
           f. No previous data → maintain (mark as "first session baseline")

        4. Recovery and frequency awareness:
           - Look at ALL recent sessions across ALL routines, not just this routine
           - If the same muscle group was trained in the last 2 days: DO NOT suggest weight increases. Use "maintain" and note recovery.
           - IMPORTANT: Your summary MUST be consistent with your goals. If you say "recovery day" or "reduced loads," then DO NOT suggest weight increases. If you suggest weight increases, the summary should reflect progression, not recovery.

        5. Deload transition:
           - If the most recent session shows significantly lower weight or higher reps than previous sessions (deload pattern), today should return to pre-deload working weights — NOT jump above them
           - Action should be "maintain" with reasoning: "Returning to pre-deload working weight of Xkg"

        6. Reasoning MUST cite specific data:
           - BAD: "Inconsistent rep completion at current weight"
           - GOOD: "Last session: 30kg for 15/13/11 — 4-rep drop across sets. Aim for 30kg×15/14/13 before progressing"
           - BAD: "Still working on consistency"
           - GOOD: "Two sessions at 30kg: 15/15/14 then 15/13/11 — not yet stable. Hold 30kg, target 15/15/14"

        7. Use "increase_reps" action when the client should stay at the same weight but push for more reps. Don't use "maintain" for this — "maintain" means keep doing exactly the same thing.

        8. For bodyweight exercises (0 kg): suggest rep targets only, use 0 for weight.
        9. suggested_weight and suggested_reps are for the WORKING sets (not warm-up).

        10. Rep pattern awareness:
           - When reps decrease across sets (e.g., 12/10/8), this is normal fatigue — base targets on SET 1 performance, not the average.
           - When weight drops between sets, this may be a drop set — acknowledge it and suggest targets based on the top set.
           - When reps fall below the target range minimum, this may indicate the weight is too heavy — suggest maintaining or decreasing.
           - Account for intentional rep schemes (descending, pyramid). Suggest targets that match the observed pattern, not a flat rep target.

        11. Drop set recommendations:
           - Use "add_drop_set" action when suggesting the client add a drop set after their working sets.
           - When action is "add_drop_set": set suggested_weight/suggested_reps to the WORKING set targets, and provide drop_set_weight (75% of working weight, rounded to nearest 2.5kg) and drop_set_reps (same or slightly higher than working reps).
           - Suggest drop sets when: plateaued 2+ sessions on isolation/cable exercises, OR client needs extra volume for lagging muscle groups, OR as a finisher technique.
           - Do NOT suggest drop sets on heavy compound barbell movements (squats, deadlifts, bench press).
           - For exercises where drop sets are NOT recommended, leave drop_set_weight and drop_set_reps as null.
        """

        do {
            let response = try await ClaudeClient.shared.send(
                systemPrompt: systemPrompt,
                userMessage: userMessage
            )

            guard let result = parseSessionGoals(response) else {
                print("[AI] Failed to parse session goals response")
                return nil
            }

            // Cache in Supabase
            let insert = SessionGoalInsert(
                routineName: routineName,
                goalDate: today,
                goalsJson: response
            )
            do {
                try await sb.postBatch("session_goals", body: [insert])
            } catch {
                print("[AI] Failed to cache session goals: \(error.localizedDescription)")
            }

            return result
        } catch {
            print("[AI] Session goals error: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Weight trend AI insight

    func generateWeightInsight() async -> WeightInsight? {
        let today = isoDate(Date())

        // Check if latest weight is from today (fresh weigh-in)
        let latestWeighIn = bodyWeightLog.last.map { isoDate($0.loggedAt) } ?? ""
        let hasNewWeighIn = latestWeighIn == today

        // Return in-memory cache if it already covers today's weigh-in
        if let cached = cachedWeightInsight, weightInsightDate == today, !hasNewWeighIn || weightInsightDate == latestWeighIn {
            return cached
        }

        // Check Supabase cache — but only if no new weigh-in since cache was created
        if let rows: [SessionGoalRow] = await sb.tryGet(
            "session_goals?routine_name=eq.weight_insight&goal_date=eq.\(today)&limit=1"
        ), let row = rows.first {
            // If today's weigh-in came after the cache, skip it and make a fresh call
            if let createdAt = row.createdAt as Date?,
               let latestWeight = bodyWeightLog.last,
               latestWeight.loggedAt > createdAt {
                // New weight since cache — fall through to fresh call
            } else {
                let result = parseWeightInsight(row.goalsJson)
                cachedWeightInsight = result
                weightInsightDate = today
                return result
            }
        }

        let allWeights = bodyWeightLog
        guard allWeights.count >= 3 else { return nil }

        // Send ALL available data so the AI can see the full trend
        let recentWindow = min(7, allWeights.count)
        let previousWindow = min(14, max(0, allWeights.count - recentWindow))

        let recent = Array(allWeights.suffix(recentWindow))
        let previous = Array(allWeights.dropLast(min(recentWindow, allWeights.count)).suffix(previousWindow))

        var lines: [String] = []

        // Include full 30-day summary stats
        let weights = allWeights.map(\.weightKg)
        let oldest = allWeights.first!, newest = allWeights.last!
        let totalChange = newest.weightKg - oldest.weightKg
        let daysBetween = max(1, Calendar.current.dateComponents([.day], from: oldest.loggedAt, to: newest.loggedAt).day ?? 1)
        let weeklyRate = totalChange / Double(daysBetween) * 7.0

        lines.append("SUMMARY (\(allWeights.count) entries over \(daysBetween) days):")
        lines.append("  Start: \(oldest.dayLabel) — \(oldest.weightKg.clean) kg")
        lines.append("  Latest: \(newest.dayLabel) — \(newest.weightKg.clean) kg")
        lines.append("  Total change: \(totalChange >= 0 ? "+" : "")\(String(format: "%.1f", totalChange)) kg")
        lines.append("  Weekly rate: \(String(format: "%.2f", weeklyRate)) kg/week")
        lines.append("  Low: \(String(format: "%.1f", weights.min() ?? 0)) kg | High: \(String(format: "%.1f", weights.max() ?? 0)) kg | Avg: \(String(format: "%.1f", weights.reduce(0, +) / Double(weights.count))) kg")
        lines.append("")

        if !previous.isEmpty {
            lines.append("Previous \(previous.count) entries:")
            for w in previous {
                lines.append("  \(w.dayLabel): \(w.weightKg.clean) kg")
            }
            lines.append("")
        }
        lines.append("Most recent \(recentWindow) entries:")
        for w in recent {
            lines.append("  \(w.dayLabel): \(w.weightKg.clean) kg")
        }

        // Compute 7-day moving average for the last 2 weeks to show trend
        if allWeights.count >= 14 {
            let last14 = Array(allWeights.suffix(14))
            let firstWeekAvg = last14.prefix(7).map(\.weightKg).reduce(0, +) / 7.0
            let secondWeekAvg = last14.suffix(7).map(\.weightKg).reduce(0, +) / 7.0
            lines.append("")
            lines.append("7-day moving average:")
            lines.append("  2 weeks ago: \(String(format: "%.1f", firstWeekAvg)) kg")
            lines.append("  Last week: \(String(format: "%.1f", secondWeekAvg)) kg")
            lines.append("  Week-over-week: \(String(format: "%.2f", secondWeekAvg - firstWeekAvg)) kg")
        }

        // Add user's phase goals if available
        if let goals = userPhaseGoals {
            lines.append("")
            lines.append("User's current plan:")
            lines.append("  Phase: \(goals.phaseLabel)")
            lines.append("  Target: \(goals.targetCalories) cal | \(goals.targetProtein)P / \(goals.targetCarbs)C / \(goals.targetFat)F")
            lines.append("  End date: \(goals.endDate)")
        }

        let systemPrompt = """
        You are a physique coach and nutrition expert analyzing body weight data. Your job is to read the FULL trend — not just the last 2 data points — and give actionable calorie advice.

        You MUST respond with ONLY valid JSON, no markdown, no code fences, no extra text.
        Use this exact JSON structure:
        {
          "trend": "losing|gaining|stable|fluctuating",
          "weekly_rate": -0.5,
          "suggestion": "2-3 sentence recommendation — cite specific numbers from the data. Reference the user's phase, target calories, and what adjustment (if any) to make.",
          "calorie_action": "increase|maintain|decrease|hold",
          "confidence": "high|medium|low"
        }

        CRITICAL RULES — follow this decision tree:

        1. TREND DETECTION (use the SUMMARY stats, not individual days):
           - Look at total change over the full period AND the 7-day moving average comparison
           - A clear downtrend (weekly rate < -0.3 kg/week) = "losing"
           - A clear uptrend (weekly rate > +0.3 kg/week) = "gaining"
           - Flat within ±0.3 kg/week = "stable"
           - "fluctuating" = ONLY use if there is genuinely no trend (e.g. up 1kg then down 1kg repeatedly with no direction). A downtrend with normal daily noise is NOT "fluctuating" — it is "losing".

        2. DAILY NOISE vs REAL TREND:
           - Body weight fluctuates 0.5-1.5 kg day-to-day from water, sodium, food volume, bowel movements
           - NEVER call a clear multi-week trend "volatile" or "fluctuating" because of normal daily variation
           - Use the 7-day moving average comparison to filter noise
           - A 0.5-1.0 kg day-to-day swing is NORMAL — do not flag it

        3. PHASE-SPECIFIC ADVICE:
           - "Post-Cut" / "Reverse Diet": User is INCREASING calories after a deficit. Goal = metabolic recovery.
             * Weight still dropping → calories should increase FASTER (metabolism running hot, don't stay in unnecessary deficit)
             * Weight stable → on track, continue planned calorie increases
             * Weight rising 0.2-0.5 kg/week → normal water/glycogen refill, continue plan
             * Weight rising >0.5 kg/week after week 1 → hold current calories for an extra week
             * Frame ALL advice as metabolic recovery, NOT fat loss
           - "Cutting": Target 0.3-0.7 kg/week loss. Faster than 0.7 = too aggressive, suggest +100 cal. Slower than 0.3 = stalled, hold or reduce 100 cal.
           - "Bulking": Target 0.2-0.4 kg/week gain. Faster = reduce surplus. Not gaining after 2 weeks = increase by 100-150 cal.
           - No phase = detect from data pattern.

        4. SUGGESTION QUALITY:
           - MUST reference specific numbers: "You've lost X.X kg over Y days (Z kg/week)"
           - MUST reference the user's target calories if provided
           - MUST give a concrete recommendation (increase by how much, maintain at what level, etc.)
           - Keep to 2-3 punchy sentences. No filler.

        5. CONFIDENCE:
           - "high" = 10+ data points, clear trend, consistent direction
           - "medium" = 5-9 data points, or minor inconsistencies
           - "low" = <5 data points, or genuinely contradictory data

        6. WEEKLY RATE:
           - Use the calculated weekly rate from the SUMMARY, not an estimate from 2 days
           - Round to 2 decimal places
        """

        do {
            let response = try await ClaudeClient.shared.send(
                systemPrompt: systemPrompt,
                userMessage: lines.joined(separator: "\n")
            )
            let result = parseWeightInsight(response)
            cachedWeightInsight = result
            weightInsightDate = today

            // Persist in Supabase
            let insert = SessionGoalInsert(
                routineName: "weight_insight",
                goalDate: today,
                goalsJson: response
            )
            try? await sb.postBatch("session_goals", body: [insert])

            return result
        } catch {
            print("[AI] Weight insight error: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Photo comparison AI

    func generatePhotoComparison(latestImages: [(Data, String)], previousImages: [(Data, String)], latestDate: String, previousDate: String) async -> PhotoInsight? {
        // Check Supabase cache for today's comparison
        let cacheKey = "photo_insight_\(latestDate)"
        let encoded = cacheKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cacheKey
        if let rows: [SessionGoalRow] = await sb.tryGet(
            "session_goals?routine_name=eq.\(encoded)&limit=1"
        ), let row = rows.first {
            return parsePhotoInsight(row.goalsJson)
        }

        // Build image pairs: previous first, then latest
        var allImages: [(Data, String)] = []
        for (data, pose) in previousImages {
            allImages.append((data, "BEFORE (\(previousDate)) — \(pose) pose"))
        }
        for (data, pose) in latestImages {
            allImages.append((data, "AFTER (\(latestDate)) — \(pose) pose"))
        }

        let systemPrompt = """
        You are an expert physique coach analyzing progress photos. Compare the BEFORE and AFTER photos.
        You MUST respond with ONLY valid JSON, no markdown, no code fences, no extra text.
        Use this exact JSON structure:
        {
          "summary": "2-3 sentence overall comparison of physique changes",
          "changes": [
            {
              "area": "shoulders|chest|arms|back|abs|legs|overall_leanness|posture",
              "observation": "What specifically changed in this area",
              "direction": "improved|maintained|declined"
            }
          ],
          "overall_progress": "significant|moderate|minimal|no_change",
          "encouragement": "1 motivational sentence acknowledging the work"
        }
        Rules:
        - Compare BEFORE photos to AFTER photos for the same pose when available
        - Focus on visible muscle development, definition, leanness, and proportions
        - Be honest but encouraging — point out real changes, don't fabricate them
        - If time between photos is short, acknowledge that meaningful change takes time
        - Include 3-6 body areas in the changes array
        - Consider lighting and angle differences before attributing changes to muscle growth
        """

        let userText = "Compare my progress photos from \(previousDate) (BEFORE) to \(latestDate) (AFTER). Time between sessions: these are my progress check-in photos."

        do {
            let response = try await ClaudeClient.shared.sendWithImages(
                systemPrompt: systemPrompt,
                userText: userText,
                images: allImages
            )

            guard let result = parsePhotoInsight(response) else {
                print("[AI] Failed to parse photo insight response")
                return nil
            }

            // Cache in Supabase
            let insert = SessionGoalInsert(
                routineName: cacheKey,
                goalDate: latestDate,
                goalsJson: response
            )
            try? await sb.postBatch("session_goals", body: [insert])

            return result
        } catch {
            print("[AI] Photo comparison error: \(error.localizedDescription)")
            return nil
        }
    }

    func loadCachedPhotoInsight(latestDate: String) async -> PhotoInsight? {
        let cacheKey = "photo_insight_\(latestDate)"
        let encoded = cacheKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cacheKey
        guard let rows: [SessionGoalRow] = await sb.tryGet(
            "session_goals?routine_name=eq.\(encoded)&limit=1"
        ), let row = rows.first else { return nil }
        return parsePhotoInsight(row.goalsJson)
    }

    private func parsePhotoInsight(_ json: String) -> PhotoInsight? {
        var cleaned = json.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```json") { cleaned = String(cleaned.dropFirst(7)) }
        else if cleaned.hasPrefix("```") { cleaned = String(cleaned.dropFirst(3)) }
        if cleaned.hasSuffix("```") { cleaned = String(cleaned.dropLast(3)) }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = cleaned.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(PhotoInsight.self, from: data)
    }

    private func parseWeightInsight(_ json: String) -> WeightInsight? {
        var cleaned = json.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```json") { cleaned = String(cleaned.dropFirst(7)) }
        else if cleaned.hasPrefix("```") { cleaned = String(cleaned.dropFirst(3)) }
        if cleaned.hasSuffix("```") { cleaned = String(cleaned.dropLast(3)) }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = cleaned.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(WeightInsight.self, from: data)
    }

    private func parseSessionGoals(_ json: String) -> SessionGoalsResult? {
        var cleaned = json.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```json") { cleaned = String(cleaned.dropFirst(7)) }
        else if cleaned.hasPrefix("```") { cleaned = String(cleaned.dropFirst(3)) }
        if cleaned.hasSuffix("```") { cleaned = String(cleaned.dropLast(3)) }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = cleaned.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(SessionGoalsResult.self, from: data)
    }

    private func isoDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }

    // MARK: - Private helpers

    private struct RoutineExerciseInfo {
        let name: String
        let targetSets: Int
        let targetRepsMin: Int?
        let targetRepsMax: Int?
        let equipment: String?
    }

    private func fetchPreviousSessionSets(routineName: String, excludeWorkoutId: UUID) async -> [WorkoutSet] {
        let encoded = routineName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? routineName
        guard let workouts: [Workout] = await sb.tryGet(
            "workouts?select=id&routine_name=eq.\(encoded)&finished_at=not.is.null&order=started_at.desc&limit=2"
        ) else { return [] }
        // Find the previous workout (not the current one)
        guard let prevWk = workouts.first(where: { $0.id != excludeWorkoutId }) else { return [] }
        return await sb.tryGet(
            "workout_sets?select=*&workout_id=eq.\(prevWk.id)&order=exercise_name.asc,set_number.asc"
        ) ?? []
    }

    private func fetchRoutineExercises(routineName: String) async -> [RoutineExerciseInfo] {
        let encoded = routineName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? routineName
        struct RoutineRow: Decodable { let id: UUID }
        guard let routines: [RoutineRow] = await sb.tryGet(
            "routines?select=id&name=eq.\(encoded)&limit=1"
        ), let routine = routines.first else { return [] }

        struct RERow: Decodable {
            let targetSets: Int
            let targetRepsMin: Int?
            let targetRepsMax: Int?
            let exercises: ExInfo
            struct ExInfo: Decodable {
                let name: String
                let equipment: String?
            }
            enum CodingKeys: String, CodingKey {
                case targetSets = "target_sets"
                case targetRepsMin = "target_reps_min"
                case targetRepsMax = "target_reps_max"
                case exercises
            }
        }
        let rows: [RERow] = await sb.tryGet(
            "routine_exercises?select=target_sets,target_reps_min,target_reps_max,exercises(name,equipment)" +
            "&routine_id=eq.\(routine.id)&order=position"
        ) ?? []
        return rows.map { RoutineExerciseInfo(
            name: $0.exercises.name,
            targetSets: $0.targetSets,
            targetRepsMin: $0.targetRepsMin,
            targetRepsMax: $0.targetRepsMax,
            equipment: $0.exercises.equipment
        )}
    }

    private func buildAnalysisPrompt(routineName: String, sets: [WorkoutSet], previousSets: [WorkoutSet], routineExercises: [RoutineExerciseInfo]) -> String {
        let grouped = Dictionary(grouping: sets, by: \.exerciseName)
        let prevGrouped = Dictionary(grouping: previousSets, by: \.exerciseName)
        let reInfo = Dictionary(uniqueKeysWithValues: routineExercises.map { ($0.name, $0) })

        let orderedNames = grouped.keys.sorted {
            let t0 = grouped[$0]?.map(\.loggedAt).min() ?? .distantPast
            let t1 = grouped[$1]?.map(\.loggedAt).min() ?? .distantPast
            return t0 < t1
        }

        // Pre-calculate total volume (LLMs are bad at arithmetic)
        let todayVolume = sets.reduce(0.0) { $0 + $1.weightKg * Double($1.reps) }
        let prevVolume = previousSets.isEmpty ? nil : previousSets.reduce(0.0) { $0 + $1.weightKg * Double($1.reps) }

        var lines: [String] = ["Routine: \(routineName)", ""]

        // Include pre-calculated volumes
        lines.append("PRE-CALCULATED VOLUMES (use these exact numbers, do NOT recalculate):")
        lines.append("  Today's total volume: \(String(format: "%.1f", todayVolume)) kg")
        if let prev = prevVolume {
            let pct = (todayVolume - prev) / prev * 100
            lines.append("  Previous session total volume: \(String(format: "%.1f", prev)) kg")
            lines.append("  Change: \(String(format: "%+.1f", pct))%")
        } else {
            lines.append("  Previous session total volume: no data")
        }
        lines.append("")

        for name in orderedNames {
            let exSets = (grouped[name] ?? []).sorted { $0.setNumber < $1.setNumber }
            let info = reInfo[name]
            let exVolume = exSets.reduce(0.0) { $0 + $1.weightKg * Double($1.reps) }

            // Exercise header with target rep range
            var header = "\(name)"
            if let info {
                let min = info.targetRepsMin ?? 0
                let max = info.targetRepsMax ?? 0
                header += " (target: \(info.targetSets) sets \u{00D7} \(min)\u{2013}\(max) reps"
                if let eq = info.equipment { header += ", \(eq)" }
                header += ")"
            }
            lines.append(header + ":")

            // Today's sets with pattern detection
            lines.append("  Today (volume: \(String(format: "%.0f", exVolume)) kg):")
            for s in exSets {
                let weightStr = s.weightKg == 0 ? "BW" : "\(s.weightKg.clean)kg"
                lines.append("    Set \(s.setNumber): \(weightStr) \u{00D7} \(s.reps) reps")
            }
            // Flag rep/weight patterns
            let repsArray = exSets.map(\.reps)
            let weightsArray = exSets.map(\.weightKg)
            if repsArray.count >= 2 {
                let isDescending = zip(repsArray, repsArray.dropFirst()).allSatisfy { $0 >= $1 } && repsArray.first != repsArray.last
                let isDropSet = zip(weightsArray, weightsArray.dropFirst()).contains { $0 > $1 }
                if let targetMin = info?.targetRepsMin, targetMin > 0 {
                    let failedSets = repsArray.filter { $0 < targetMin }
                    if !failedSets.isEmpty {
                        lines.append("  [PATTERN: FAILURE — \(failedSets.count) set(s) below target min of \(targetMin)]")
                    }
                }
                if isDropSet {
                    lines.append("  [PATTERN: DROP SET — weight decreased across sets]")
                } else if isDescending {
                    lines.append("  [PATTERN: DESCENDING REPS — normal fatigue (\(repsArray.map(String.init).joined(separator: "/")))]")
                }
            }

            // Previous session sets (if available)
            if let prevSets = prevGrouped[name]?.sorted(by: { $0.setNumber < $1.setNumber }), !prevSets.isEmpty {
                let prevExVolume = prevSets.reduce(0.0) { $0 + $1.weightKg * Double($1.reps) }
                lines.append("  Previous session (volume: \(String(format: "%.0f", prevExVolume)) kg):")
                for s in prevSets {
                    let weightStr = s.weightKg == 0 ? "BW" : "\(s.weightKg.clean)kg"
                    lines.append("    Set \(s.setNumber): \(weightStr) \u{00D7} \(s.reps) reps")
                }
            } else {
                lines.append("  Previous session: no data")
            }

            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private func parseAnalysis(_ json: String) -> AIAnalysisResult? {
        // Strip markdown code fences if present
        var cleaned = json.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```json") {
            cleaned = String(cleaned.dropFirst(7))
        } else if cleaned.hasPrefix("```") {
            cleaned = String(cleaned.dropFirst(3))
        }
        if cleaned.hasSuffix("```") {
            cleaned = String(cleaned.dropLast(3))
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(AIAnalysisResult.self, from: data)
    }

    private func storeSuggestions(workoutId: UUID, sets: [WorkoutSet], suggestions: [AISuggestion]) async {
        // Build exercise ID lookup from sets
        var exerciseIds: [String: UUID] = [:]
        for s in sets {
            if exerciseIds[s.exerciseName] == nil {
                exerciseIds[s.exerciseName] = s.exerciseId
            }
        }

        var inserts: [AISuggestionInsert] = []
        for s in suggestions {
            guard let exId = exerciseIds[s.exerciseName] else { continue }
            inserts.append(AISuggestionInsert(
                workoutId: workoutId,
                exerciseId: exId,
                exerciseName: s.exerciseName,
                suggestedWeight: s.suggestedWeight,
                suggestedReps: s.suggestedReps,
                reason: s.reason,
                status: "pending"
            ))
        }

        guard !inserts.isEmpty else { return }
        do {
            try await sb.postBatch("ai_suggestions", body: inserts)
        } catch {
            print("[AI] Failed to store suggestions: \(error.localizedDescription)")
        }
    }

    // MARK: - User Phase Goals (stored in session_goals with key "user_phase_goals")

    func loadUserPhaseGoals() async {
        guard let rows: [SessionGoalRow] = await sb.tryGet(
            "session_goals?routine_name=eq.user_phase_goals&order=created_at.desc&limit=1"
        ), let row = rows.first else { return }
        var cleaned = row.goalsJson.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```json") { cleaned = String(cleaned.dropFirst(7)) }
        else if cleaned.hasPrefix("```") { cleaned = String(cleaned.dropFirst(3)) }
        if cleaned.hasSuffix("```") { cleaned = String(cleaned.dropLast(3)) }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = cleaned.data(using: .utf8) else { return }
        userPhaseGoals = try? JSONDecoder().decode(UserPhaseGoals.self, from: data)
    }

    func saveUserPhaseGoals(_ goals: UserPhaseGoals) async {
        userPhaseGoals = goals
        guard let jsonData = try? JSONEncoder().encode(goals),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }

        let today = isoDate(Date())
        // Delete old goals entry first
        try? await sb.delete("session_goals?routine_name=eq.user_phase_goals")

        let insert = SessionGoalInsert(
            routineName: "user_phase_goals",
            goalDate: today,
            goalsJson: jsonString
        )
        try? await sb.postBatch("session_goals", body: [insert])

        // Clear cached weight insight (both in-memory and Supabase) so next analysis uses new goals
        cachedWeightInsight = nil
        weightInsightDate = ""
        try? await sb.delete("session_goals?routine_name=eq.weight_insight")
    }
}
