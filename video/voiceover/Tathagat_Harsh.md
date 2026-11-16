# Voiceover script: Tathagat Harsh

**Roll no.** 2401010477  ·  **Your file to explain in the viva:** `cache_controller.v`

## You need to record **2 voice notes**

### Voice note 1: Opening  ·  save as `T1.m4a`

- Plays at **0:00 → 0:30** in the film. Your speaking (not counting the pauses) should fit in **0:30** (60 words, normal pace). The pauses get cut out.
- Read these **4 lines in order**. **Pause ~2 seconds after each line** (count "one, two" in your head).

1. Where does address 0x1000 live? In a direct-mapped cache: in exactly one line.
2. This is our CSA222 project: a Direct-Mapped Cache Controller in Verilog.
3. I'm Tathagat Harsh, and with me are M S Thejas, Garv Verma, Parv Goyal and Vaibhav Rajput.
4. A cache is a small, fast SRAM between the CPU and slow DRAM. It works because programs have locality.

### Voice note 2: Controller FSM  ·  save as `T2.m4a`

- Plays at **2:10 → 3:00** in the film. Your speaking (not counting the pauses) should fit in **0:50** (69 words, normal pace). The pauses get cut out.
- Read these **5 lines in order**. **Pause ~2 seconds after each line** (count "one, two" in your head).

1. I designed the controller: a four-state finite state machine.
2. IDLE latches the request. COMPARE checks the tag. A read miss goes to ALLOCATE and waits ten cycles for memory.
3. A read hit finishes in a single cycle.
4. Every write goes to WRITE_MEM: write-through, no-write-allocate. Memory is always up to date, so no dirty bits.
5. The hit and miss counters live here, so the hardware measures its own hit rate.

---

## How to record

1. Quiet room, phone 15–20 cm from your mouth. Phone voice recorder or a WhatsApp voice note is fine.
2. Press record, wait 1 second, read line 1, **pause 2 seconds**, read line 2, … wait 1 second, stop.
3. The pauses matter: they are how your recording gets cut and placed under the right animation.
4. Speak naturally, like explaining to a friend. A small slip is fine; a big one: pause, then repeat that line.
5. Send the files to the group named `T1.m4a`, `T2.m4a`.

To practise: play `video/film/out/dm_cache_film.mp4` and read along with the captions when your name appears.
