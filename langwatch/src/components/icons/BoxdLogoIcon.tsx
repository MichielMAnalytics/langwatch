import React from "react";

function getBoxPath(size: number): string {
  const r = 2;
  const ri = 2;
  const n = size * 0.2;
  const notchTop = size - n;
  const notchRight = n;

  return `M ${r} 0 L ${size - r} 0 A ${r} ${r} 0 0 1 ${size} ${r} L ${size} ${size - r} A ${r} ${r} 0 0 1 ${size - r} ${size} L ${notchRight + r} ${size} A ${r} ${r} 0 0 1 ${notchRight} ${size - r} L ${notchRight} ${notchTop + ri} A ${ri} ${ri} 0 0 0 ${notchRight - ri} ${notchTop} L ${r} ${notchTop} A ${r} ${r} 0 0 1 0 ${notchTop - r} L 0 ${r} A ${r} ${r} 0 0 1 ${r} 0 Z`;
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
