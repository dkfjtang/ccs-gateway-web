import { CSS } from "@dnd-kit/utilities";
import { DndContext, closestCenter } from "@dnd-kit/core";
import {
  SortableContext,
  useSortable,
  verticalListSortingStrategy,
} from "@dnd-kit/sortable";
import type { CSSProperties } from "react";
import type { Provider } from "@/types";
import type { AppId } from "@/lib/api";
import { useDragSort } from "@/hooks/useDragSort";
import { ProviderCard } from "@/components/providers/ProviderCard";
import type { ProviderCardItemProps } from "@/components/providers/ProviderList";

interface ProviderListDndProps {
  providers: Record<string, Provider>;
  appId: AppId;
  desktopHelpersEnabled: boolean;
  filteredProviders: Provider[];
  getItemProps: (provider: Provider) => ProviderCardItemProps;
}

export function ProviderListDnd({
  providers,
  appId,
  desktopHelpersEnabled,
  filteredProviders,
  getItemProps,
}: ProviderListDndProps) {
  const { sensors, handleDragEnd } = useDragSort(providers, appId, {
    desktopHelpersEnabled,
  });

  return (
    <DndContext
      sensors={sensors}
      collisionDetection={closestCenter}
      onDragEnd={handleDragEnd}
    >
      <SortableContext
        items={filteredProviders.map((provider) => provider.id)}
        strategy={verticalListSortingStrategy}
      >
        <div className="space-y-3">
          {filteredProviders.map((provider) => (
            <SortableProviderCard
              key={provider.id}
              provider={provider}
              itemProps={getItemProps(provider)}
            />
          ))}
        </div>
      </SortableContext>
    </DndContext>
  );
}

interface SortableProviderCardProps {
  provider: Provider;
  itemProps: ProviderCardItemProps;
}

function SortableProviderCard({ provider, itemProps }: SortableProviderCardProps) {
  const {
    setNodeRef,
    attributes,
    listeners,
    transform,
    transition,
    isDragging,
  } = useSortable({ id: provider.id });

  const style: CSSProperties = {
    transform: CSS.Transform.toString(transform),
    transition,
  };

  return (
    <div ref={setNodeRef} style={style}>
      <ProviderCard
        {...itemProps}
        dragHandleProps={{
          attributes,
          listeners,
          isDragging,
        }}
      />
    </div>
  );
}
