# Voiceover script: Garv Verma

**Roll no.** 2401010168  ·  **Your file to explain in the viva:** `addr_decoder.v + tag_comparator.v`

## You need to record **1 voice note**

### Voice note 1: Address → Line  ·  save as `G1.m4a`

- Plays at **0:30 → 1:20** in the film. Your speaking (not counting the pauses) should fit in **0:50** (73 words, normal pace). The pauses get cut out.
- Read these **5 lines in order**. **Pause ~2 seconds after each line** (count "one, two" in your head).

1. Our cache is 1 KB with 16-byte blocks, so it has 64 lines.
2. A 32-bit address splits into a 22-bit tag, a 6-bit index and a 4-bit offset.
3. Direct-mapped means each block has exactly one possible line, chosen by the index. Same index means a fight.
4. My tag comparator gives: hit = valid AND stored tag equals request tag.
5. If the valid bit is 0, it's a miss, even when the tags match.

---

## How to record

1. Quiet room, phone 15–20 cm from your mouth. Phone voice recorder or a WhatsApp voice note is fine.
2. Press record, wait 1 second, read line 1, **pause 2 seconds**, read line 2, … wait 1 second, stop.
3. The pauses matter: they are how your recording gets cut and placed under the right animation.
4. Speak naturally, like explaining to a friend. A small slip is fine; a big one: pause, then repeat that line.
5. Send the file to the group named `G1.m4a`.

To practise: play `video/film/out/dm_cache_film.mp4` and read along with the captions when your name appears.
