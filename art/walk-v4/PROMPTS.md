# Gang 2: einfacher Wechsel von hellem und dunklem Bein

Erstellt mit dem eingebauten Bildgenerator (`imagegen`). Jonas wurde vom Nutzer als Bildfolge bestätigt. Lena verwendet dieselben vollständigen Posen. Das helle Bein bleibt kameranah und überdeckt das dunkle, kameraferne Bein an Kreuzungen. Beide schwingen abwechselnd nach vorne und hinten; die Zwischenbilder verzichten auf hochgezogene Knie.

Quellbilder: `jonas-walk-source.png`, `lena-walk-source.png`. Runtime: `assets/walk_v4/jonas.png`, `assets/walk_v4/lena.png`. Der Import beschneidet und skaliert nur vollständige Personen; es gibt keine separaten Gliedmaßen.

## Jonas

Use case: identity-preserve.
Create a 2 by 2 sheet of FOUR COMPLETE side-view game character pictures, always facing RIGHT, on transparent background. The attached small complete person is the identity and style reference: Jonas, brown hair, blue shirt, brown trousers and rounded dark boots. Preserve his entire design and proportions, especially his thick trouser legs and boots. Keep head and torso consistent in every cell, same scale, same baseline.

The simple walk is a pendulum, with almost STRAIGHT legs, NO high knees or crouching.
CRITICAL: the leg CLOSER TO THE CAMERA is always LIGHT WARM BROWN. The leg FARTHER FROM THE CAMERA is always DARK BROWN, and is always BEHIND the light leg at overlaps. These are permanent identities, NOT lighting based on left/right position.
Top-left: LIGHT near leg stretches diagonally FORWARD to the RIGHT; DARK far leg stretches diagonally BACK to the LEFT. Near arm goes back.
Top-right: both legs nearly VERTICAL underneath the hips, crossing, LIGHT leg occludes DARK leg. Arms passing down.
Bottom-left: DARK far leg stretches diagonally FORWARD to the RIGHT; LIGHT near leg stretches diagonally BACK to the LEFT. This is the OPPOSITE step from top-left: the boot on the LEFT belongs to the LIGHT leg, the boot on the RIGHT belongs to the DARK leg. The light near leg still visibly overlaps the dark far thigh at the crotch. Near arm goes forward.
Bottom-right: both legs nearly VERTICAL underneath the hips, crossing the other way, LIGHT leg occludes DARK leg. Arms passing down.

Use a modest step width. Exactly two legs on each complete person, both connected naturally at the hips. Clear persistent light/dark trouser leg distinction from hip all the way to each boot. The complete figures must look coherent, matching the reference's warm refined game sprite art. No separate parts, no labels, no scenery, no shadows, no text. Transparent background.

## Lena

Use case: identity-preserve / style-transfer.
IMAGE 1 is the APPROVED EDIT TARGET: the user accepted these exact four complete walking poses. IMAGE 2 is the female identity reference.
Transform the four COMPLETE people in image 1 into Lena from image 2: shoulder-length brown hair, RED shirt, same brown trousers, rounded brown boots and belt. Match her whole-person design from the reference, keeping the approved target's simple four poses and their layout, near/far leg shading, leg thickness and proportions exactly.

Keep the four leg poses UNCHANGED: top left LIGHT camera-near leg forward RIGHT, DARK far leg back LEFT; top right legs almost vertical; bottom left LIGHT near leg back LEFT, DARK far leg forward RIGHT; bottom right legs almost vertical. The LIGHT leg ALWAYS overlaps the DARK leg, which stays behind in depth. Both legs stay almost straight, no high knees. Keep the arm swing from the corresponding target frame. Same full-body scale and head/foot registration in all cells.
Draw four coherent COMPLETE women. Preserve the fine warm game-sprite style. No separated limbs, no labels, no shadows, no props, no scenery. Same 2 by 2 layout. Transparent background.
