# Voiceover script: M S Thejas

**Roll no.** 2401010255  ·  **Your file to explain in the viva:** `cache_rams.v`

## You need to record **1 voice note**

### Voice note 1: Storage  ·  save as `M1.m4a`

- Plays at **1:20 → 2:10** in the film. Your speaking (not counting the pauses) should fit in **0:50** (67 words, normal pace). The pauses get cut out.
- Read these **4 lines in order**. **Pause ~2 seconds after each line** (count "one, two" in your head).

1. The cache stores everything in three arrays: valid bits, tags and data.
2. Valid bits are flip-flops: one reset clears all 64, so a garbage tag never gives a false hit.
3. On a miss the data RAM takes a whole 16-byte block in one cycle. On a write hit, just one word.
4. Direct-mapped gives the fastest hit path: one compare, no replacement policy. The cost is conflict misses.

---

## How to record

1. Quiet room, phone 15–20 cm from your mouth. Phone voice recorder or a WhatsApp voice note is fine.
2. Press record, wait 1 second, read line 1, **pause 2 seconds**, read line 2, … wait 1 second, stop.
3. The pauses matter: they are how your recording gets cut and placed under the right animation.
4. Speak naturally, like explaining to a friend. A small slip is fine; a big one: pause, then repeat that line.
5. Send the file to the group named `M1.m4a`.

To practise: play `video/film/out/dm_cache_film.mp4` and read along with the captions when your name appears.
