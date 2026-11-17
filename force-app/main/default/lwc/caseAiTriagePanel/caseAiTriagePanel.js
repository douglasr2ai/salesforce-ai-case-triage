import { LightningElement, api, wire } from "lwc";
import {
  getRecord,
  updateRecord,
  notifyRecordUpdateAvailable
} from "lightning/uiRecordApi";
import { ShowToastEvent } from "lightning/platformShowToastEvent";

import ID_FIELD from "@salesforce/schema/Case.Id";
import PRIORITY_FIELD from "@salesforce/schema/Case.Priority";
import STATUS_FIELD from "@salesforce/schema/Case.AI_Status__c";
import CATEGORY_FIELD from "@salesforce/schema/Case.AI_Category__c";
import SUGGESTED_PRIORITY_FIELD from "@salesforce/schema/Case.AI_Suggested_Priority__c";
import SENTIMENT_FIELD from "@salesforce/schema/Case.AI_Sentiment__c";
import SUMMARY_FIELD from "@salesforce/schema/Case.AI_Summary__c";
import REPLY_FIELD from "@salesforce/schema/Case.AI_Suggested_Reply__c";
import MODEL_FIELD from "@salesforce/schema/Case.AI_Model__c";
import PROCESSED_AT_FIELD from "@salesforce/schema/Case.AI_Processed_At__c";
import ERROR_FIELD from "@salesforce/schema/Case.AI_Error__c";

const FIELDS = [
  PRIORITY_FIELD,
  STATUS_FIELD,
  CATEGORY_FIELD,
  SUGGESTED_PRIORITY_FIELD,
  SENTIMENT_FIELD,
  SUMMARY_FIELD,
  REPLY_FIELD,
  MODEL_FIELD,
  PROCESSED_AT_FIELD,
  ERROR_FIELD
];

export const POLL_INTERVAL_MS = 3000;
export const MAX_POLLS = 20;

const SENTIMENT_STYLE = {
  Positive: { icon: "utility:smiley_and_people", badge: "slds-theme_success" },
  Neutral: { icon: "utility:dash", badge: "" },
  Negative: { icon: "utility:warning", badge: "slds-theme_warning" },
  Angry: { icon: "utility:error", badge: "slds-theme_error" }
};

const PRIORITY_BADGE = {
  High: "slds-theme_error",
  Medium: "slds-theme_warning",
  Low: "slds-theme_success"
};

export default class CaseAiTriagePanel extends LightningElement {
  @api recordId;

  record;
  error;
  isBusy = false;
  pollCount = 0;
  pollTimer;

  @wire(getRecord, { recordId: "$recordId", fields: FIELDS })
  wiredRecord(result) {
    if (result.data) {
      this.record = result.data;
      this.error = undefined;
      if (this.isPending) {
        this.schedulePoll();
      } else {
        this.stopPolling();
      }
    } else if (result.error) {
      this.error = result.error;
      this.record = undefined;
    }
  }

  disconnectedCallback() {
    this.stopPolling();
  }

  // ---------- field access ----------

  value(field) {
    return this.record?.fields?.[field.fieldApiName]?.value ?? null;
  }

  get status() {
    return this.value(STATUS_FIELD);
  }
  get category() {
    return this.value(CATEGORY_FIELD);
  }
  get sentiment() {
    return this.value(SENTIMENT_FIELD);
  }
  get suggestedPriority() {
    return this.value(SUGGESTED_PRIORITY_FIELD);
  }
  get currentPriority() {
    return this.value(PRIORITY_FIELD);
  }
  get summary() {
    return this.value(SUMMARY_FIELD);
  }
  get suggestedReply() {
    return this.value(REPLY_FIELD);
  }
  get model() {
    return this.value(MODEL_FIELD);
  }
  get processedAt() {
    return this.value(PROCESSED_AT_FIELD);
  }
  get errorDetails() {
    return this.value(ERROR_FIELD);
  }

  // ---------- view state ----------

  get isLoading() {
    return !this.record && !this.error;
  }
  get isPending() {
    return this.status === "Pending" || this.status === "Processing";
  }
  get isCompleted() {
    return this.status === "Completed";
  }
  get isFailed() {
    return this.status === "Failed";
  }
  get isNotTriaged() {
    return Boolean(this.record) && !this.status;
  }
  get loadErrorMessage() {
    return this.error?.body?.message ?? "Could not load the AI triage data.";
  }

  get sentimentIcon() {
    return SENTIMENT_STYLE[this.sentiment]?.icon ?? "utility:dash";
  }
  get sentimentBadgeClass() {
    return SENTIMENT_STYLE[this.sentiment]?.badge ?? "";
  }
  get priorityBadgeClass() {
    return PRIORITY_BADGE[this.suggestedPriority] ?? "";
  }
  get canApplyPriority() {
    return (
      Boolean(this.suggestedPriority) &&
      this.suggestedPriority !== this.currentPriority
    );
  }
  get applyPriorityDisabled() {
    return this.isBusy || !this.canApplyPriority;
  }
  get runDisabled() {
    return this.isBusy || this.isPending;
  }
  get runLabel() {
    return this.status ? "Run again" : "Run AI triage";
  }
  get footerSeparator() {
    // Template whitespace is collapsed, so the spaces live in an expression.
    return " \u00b7 ";
  }
  get copyDisabled() {
    return !this.suggestedReply;
  }

  // ---------- actions ----------

  async handleRun() {
    this.pollCount = 0;
    await this.save(
      { [STATUS_FIELD.fieldApiName]: "Pending" },
      "AI triage started",
      "The analysis will appear here in a few seconds."
    );
  }

  async handleApplyPriority() {
    await this.save(
      { [PRIORITY_FIELD.fieldApiName]: this.suggestedPriority },
      "Priority updated",
      `Case priority set to ${this.suggestedPriority}.`
    );
  }

  async handleCopyReply() {
    try {
      await navigator.clipboard.writeText(this.suggestedReply);
      this.toast(
        "Copied",
        "Suggested reply copied to the clipboard.",
        "success"
      );
    } catch {
      this.toast(
        "Copy failed",
        "Your browser blocked clipboard access.",
        "error"
      );
    }
  }

  async save(fields, title, message) {
    this.isBusy = true;
    try {
      await updateRecord({
        fields: { [ID_FIELD.fieldApiName]: this.recordId, ...fields }
      });
      this.toast(title, message, "success");
    } catch (e) {
      this.toast(
        "Something went wrong",
        e?.body?.message ?? e?.message ?? "Unknown error",
        "error"
      );
    } finally {
      this.isBusy = false;
    }
  }

  // ---------- polling while the async job runs ----------

  schedulePoll() {
    if (this.pollTimer || this.pollCount >= MAX_POLLS) {
      return;
    }
    // The triage runs in a Queueable job, so we poll the record until it settles.
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.pollTimer = setTimeout(() => this.poll(), POLL_INTERVAL_MS);
  }

  async poll() {
    this.pollTimer = undefined;
    this.pollCount += 1;
    try {
      // Tells Lightning Data Service the record is stale so @wire(getRecord) refetches it.
      await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
    } catch {
      // A failed refresh is retried on the next tick.
    }
    // Keep polling even when nothing changed (the wire only re-emits on changes).
    if (this.isPending) {
      this.schedulePoll();
    }
  }

  stopPolling() {
    clearTimeout(this.pollTimer);
    this.pollTimer = undefined;
    this.pollCount = 0;
  }

  toast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
}
