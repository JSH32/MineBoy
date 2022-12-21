import RgbQuant from "rgbquant";

export type FixedArray<
  T,
  N extends number,
  R extends readonly T[] = [],
> = R["length"] extends N ? R : FixedArray<T, N, readonly [T, ...R]>;

/**
 * Quantizes the frame and compresses into a small package
 *
 * @param rgbaBuf RGBA buffer of the frame
 * @param dimensions width and height of the image
 * @returns A palette and a 4-bit buffer of index references to the palette.
 * The returned image has one higher height than provided because of a imgquant bug.
 */
export const quantizeFrame = (
  rgbaBuf: number[],
  dimensions: [number, number]
): [FixedArray<number, 16>, Buffer] => {
  // Create 16 palette from screen
  const quant = new RgbQuant({ colors: 16 });
  quant.sample(rgbaBuf, dimensions[0]);
  const palette = quant.palette(true);

  // Fill all empty palette values with black
  for (let i = 0; i < 16; i++)
    palette[i] = palette[i] ? palette[i] : [ 0, 0, 0 ];

  // Reduced frame with color palette
  const reducedRgba = quant.reduce(rgbaBuf);

  // Convert the colors from rgba to palette indexes for smaller size
  const colorArray = [];
  for (let y = 0; y < dimensions[1]; y++) {
    for (let x = 0; x < dimensions[0]; x++) {
      const r = reducedRgba[(y * dimensions[0] + x) * 4];
      const g = reducedRgba[(y * dimensions[0] + x) * 4 + 1];
      const b = reducedRgba[(y * dimensions[0] + x) * 4 + 2];

      for (let i = 0; i < palette.length; i++) {
        if (palette[i][0] === r &&
                    palette[i][1] === g &&
                    palette[i][2] === b) {
          colorArray.push(i);
          break;
        }
      }
    }
  }

  // The last line cuts off so we push a line to the end,
  // most likely imgquant issue on lua side.
  for (let i = 0; i < dimensions[0]; i++)
    colorArray.push(0);

  // Compress the indexes to 4-bit buffer
  const output = Buffer.alloc(colorArray.length / 2);
  for (let i = 0; i < colorArray.length; i += 2)
    output.writeUInt8(colorArray[i] << 4 | colorArray[i+1], i / 2);

  return [ palette, output ];
};
