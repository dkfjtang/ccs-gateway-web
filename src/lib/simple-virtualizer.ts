import { useCallback, useEffect, useMemo, useRef, useState } from "react";

export interface VirtualItem {
  key: number;
  index: number;
  start: number;
  size: number;
  end: number;
}

interface VirtualizerOptions {
  count: number;
  getScrollElement: () => HTMLElement | null;
  estimateSize: () => number;
  overscan?: number;
  gap?: number;
}

interface ScrollToIndexOptions {
  align?: "start" | "center" | "end" | "auto";
  behavior?: ScrollBehavior;
}

export function useVirtualizer({
  count,
  getScrollElement,
  estimateSize,
  overscan = 0,
  gap = 0,
}: VirtualizerOptions) {
  const sizesRef = useRef(new Map<number, number>());
  const [revision, setRevision] = useState(0);
  const scrollElement = getScrollElement();

  useEffect(() => {
    if (!scrollElement) return undefined;

    const bump = () => setRevision((value) => value + 1);
    scrollElement.addEventListener("scroll", bump, { passive: true });

    const observer =
      typeof ResizeObserver !== "undefined" ? new ResizeObserver(bump) : null;
    observer?.observe(scrollElement);

    return () => {
      scrollElement.removeEventListener("scroll", bump);
      observer?.disconnect();
    };
  }, [scrollElement]);

  const getSize = useCallback(
    (index: number) => sizesRef.current.get(index) ?? estimateSize(),
    [estimateSize, revision],
  );

  const totalSize = useMemo(() => {
    if (count <= 0) return 0;
    let total = 0;
    for (let index = 0; index < count; index += 1) {
      total += getSize(index);
      if (index < count - 1) {
        total += gap;
      }
    }
    return total;
  }, [count, gap, getSize]);

  const virtualItems = useMemo(() => {
    if (count <= 0) return [];

    const viewportTop = scrollElement?.scrollTop ?? 0;
    const viewportHeight = scrollElement?.clientHeight ?? 0;
    const estimate = estimateSize();
    const overscanPx = overscan * estimate;
    const startBoundary = Math.max(0, viewportTop - overscanPx);
    const endBoundary = viewportTop + viewportHeight + overscanPx;

    const items: VirtualItem[] = [];
    let offset = 0;

    for (let index = 0; index < count; index += 1) {
      const size = getSize(index);
      const start = offset;
      const end = start + size;

      if (end >= startBoundary && start <= endBoundary) {
        items.push({
          key: index,
          index,
          start,
          size,
          end,
        });
      }

      offset = end + gap;
    }

    return items;
  }, [count, gap, getSize, overscan, scrollElement, revision, estimateSize]);

  const scrollToIndex = useCallback(
    (index: number, options: ScrollToIndexOptions = {}) => {
      const element = scrollElement;
      if (!element || count <= 0) return;

      const clampedIndex = Math.max(0, Math.min(index, count - 1));
      let offset = 0;
      for (let i = 0; i < clampedIndex; i += 1) {
        offset += getSize(i) + gap;
      }

      const size = getSize(clampedIndex);
      const viewportHeight = element.clientHeight;
      const align = options.align ?? "auto";

      let target = offset;
      if (align === "center") {
        target = offset - (viewportHeight - size) / 2;
      } else if (align === "end") {
        target = offset - viewportHeight + size;
      }

      const maxScroll = Math.max(0, totalSize - viewportHeight);
      const top = Math.max(0, Math.min(target, maxScroll));
      element.scrollTo({ top, behavior: options.behavior ?? "auto" });
    },
    [count, gap, getSize, scrollElement, totalSize],
  );

  const measureElement = useCallback((element: HTMLElement | null) => {
    if (!element) return;

    const index = Number(element.dataset.index);
    if (!Number.isFinite(index)) return;

    const nextSize = Math.ceil(element.getBoundingClientRect().height);
    const currentSize = sizesRef.current.get(index);
    if (currentSize === nextSize) return;

    sizesRef.current.set(index, nextSize);
    setRevision((value) => value + 1);
  }, []);

  return {
    getTotalSize: () => totalSize,
    getVirtualItems: () => virtualItems,
    measureElement,
    scrollToIndex,
  };
}
