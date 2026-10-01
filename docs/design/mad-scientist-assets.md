# docs(design): mad scientist visual assets

The native SwiftUI redesign uses the requested Color Hunt palette: burgundy `#790D16`, parchment `#E5D3AF`, ivory `#F5EFE1`, and powder blue `#AEC4D4`. Dark ink and muted brown provide readable text. Source reference: https://colorhunt.co/palette/790d16e5d3aff5efe1aec4d4.

Both original illustrations were generated with the built-in image generation tool. The supplied reference informed the goggle-wearing scientist motif. No external stock art is required.

## Hero artwork

Saved at `Sources/ZECBuyingPrice/Resources/scientist.png`. Used in wallet setup and the connected workspace sidebar. Loaded from the SwiftPM resource bundle using `NSImage`, including in the packaged application.

Generation prompt:

> Use case: illustration-story. Asset type: custom hero artwork for a native macOS Zcash acquisition research application. Create an original beautifully detailed vintage ink-and-watercolor comic illustration of an eccentric elderly scientist with tall wild white hair and large round mechanical goggles, wearing an ivory lab coat and burgundy vest, carefully studying a brass coin with a simple Z mark in his gloved hand. Surround him with a small glass distillation apparatus, blue glass flask, loose notebook pages with abstract mathematical marks, old brass microscope. Warm scholarly whimsical mood, confident expression, refined etched crosshatching, editorial graphic novel illustration, not childish. Portrait composition with waist-up scientist filling center, full hair visible, bottom ends in desk equipment. Limited palette: deep burgundy #790D16, parchment #E5D3AF, ivory #F5EFE1, powder blue #AEC4D4, dark brown ink. Background flat ivory #F5EFE1 with delicate faint technical blueprint circles. No readable text, no UI, no watermark. Reference inspiration: goggle wearing mad scientists and vintage steampunk laboratory.

## Application icon

Source: `Sources/ZECBuyingPrice/Resources/scientist-icon.png`. Packaged macOS icon: `Sources/ZECBuyingPrice/Resources/LabIcon.icns`. The build/run script copies the icon into the app bundle and references it in `Info.plist`. Apple's `sips` and `iconutil` produce the standard icon sizes.

Generation prompt:

> Use case: logo-brand. Create a square macOS application icon illustration for ZEC Buying Price, a mad scientist themed Zcash research notebook. A large original vintage scientist head with wild ivory white hair and two bold round brass mechanical goggles, expressive confident face, simplified striking ink engraving, wearing a tiny burgundy collar. Centered close cropped bust on a solid deep burgundy #790D16 square background, ivory #F5EFE1 hair, parchment #E5D3AF face, powder blue #AEC4D4 reflective goggle lenses. Strong clean silhouette readable at small icon sizes, only head and collar no scenery. Premium whimsical editorial artwork, very few fine lines, no text, no letters, no watermark, no rounded corners, full bleed square.
