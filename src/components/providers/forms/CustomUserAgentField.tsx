import { ChevronDown } from "lucide-react";
import { useTranslation } from "react-i18next";
import { USER_AGENT_PRESETS } from "@/config/userAgentPresets";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { FormLabel } from "@/components/ui/form";
import { Input } from "@/components/ui/input";
import { isValidUserAgentHeader } from "@/lib/userAgent";

interface CustomUserAgentFieldProps {
  id: string;
  value: string;
  onChange: (value: string) => void;
}

export function CustomUserAgentField({
  id,
  value,
  onChange,
}: CustomUserAgentFieldProps) {
  const { t } = useTranslation();
  const valid = isValidUserAgentHeader(value);

  return (
    <div className="space-y-2">
      <FormLabel htmlFor={id}>
        {t("providerForm.customUserAgent", {
          defaultValue: "自定义 User-Agent",
        })}
      </FormLabel>
      <div className="flex items-center gap-2">
        <Input
          id={id}
          type="text"
          value={value}
          onChange={(e) => onChange(e.target.value)}
          placeholder="Mozilla/5.0 ..."
          autoComplete="off"
          className="flex-1"
        />
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button type="button" variant="outline" className="shrink-0 gap-1">
              {t("providerForm.customUserAgentPresets", {
                defaultValue: "预设",
              })}
              <ChevronDown className="h-3.5 w-3.5 opacity-60" />
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent
            align="end"
            className="z-[200] max-h-64 overflow-y-auto"
          >
            {USER_AGENT_PRESETS.map((preset) => (
              <DropdownMenuItem
                key={preset}
                onSelect={() => onChange(preset)}
                className="font-mono text-xs"
              >
                {preset}
              </DropdownMenuItem>
            ))}
          </DropdownMenuContent>
        </DropdownMenu>
      </div>
      {valid ? (
        <p className="text-xs text-muted-foreground">
          {t("providerForm.customUserAgentHint", {
            defaultValue:
              "仅在本地代理接管后生效，会替换转发到供应商 API 请求中的 User-Agent。",
          })}
        </p>
      ) : (
        <p className="text-xs text-destructive">
          {t("providerForm.customUserAgentInvalid", {
            defaultValue:
              "User-Agent 不能包含控制字符（如换行符），否则运行时将忽略。",
          })}
        </p>
      )}
    </div>
  );
}
