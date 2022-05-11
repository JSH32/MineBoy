export type FixedArray<
  T,
  N extends number,
  R extends readonly T[] = [],
> = R['length'] extends N ? R : FixedArray<T, N, readonly [T, ...R]>