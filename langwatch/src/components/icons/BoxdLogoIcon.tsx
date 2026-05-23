import React from "react";

// boxd notched-square mark. Three independent corner radii
// (defaults calibrated for size=28, scale linearly with `size`):
//   rOuter  4 main outer corners + post-notch left
//   rNotch  bottom-edge curve into the notch
//   rInner  bulge at the notch's interior corner
// Constraint: notch width (size*0.2) must exceed rOuter + rInner.
function getBoxPath(
  size: number,
  rOuter = 3,
  rNotch = 2,
  rInner = 2,
): string {
  const r  = (rOuter * size) / 28;
  const rn = (rNotch * size) / 28;
  const ri = (rInner * size) / 28;
  const n  = size * 0.2;
  const notchTop = size - n;
  const notchRight = n;

  return [
    `M ${r} 0`,
    `L ${size - r} 0`,
    `A ${r} ${r} 0 0 1 ${size} ${r}`,
    `L ${size} ${size - r}`,
    `A ${r} ${r} 0 0 1 ${size - r} ${size}`,
    `L ${notchRight + rn} ${size}`,
    `A ${rn} ${rn} 0 0 1 ${notchRight} ${size - rn}`,
    `L ${notchRight} ${notchTop + ri}`,
    `A ${ri} ${ri} 0 0 0 ${notchRight - ri} ${notchTop}`,
    `L ${r} ${notchTop}`,
    `A ${r} ${r} 0 0 1 0 ${notchTop - r}`,
    `L 0 ${r}`,
    `A ${r} ${r} 0 0 1 ${r} 0`,
    `Z`,
  ].join(" ");
}

export function BoxdLogoIcon({
  size = 36,
  fill = "#213B41",
}: {
  size?: number;
  fill?: string;
}) {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      width={size}
      height={size}
      viewBox={`0 0 ${size} ${size}`}
      fill={fill}
    >
      <path d={getBoxPath(size)} />
    </svg>
  );
}
