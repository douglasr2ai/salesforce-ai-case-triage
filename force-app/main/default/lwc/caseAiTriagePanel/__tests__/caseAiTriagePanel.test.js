import { createElement } from "lwc";
import CaseAiTriagePanel, {
  POLL_INTERVAL_MS,
  MAX_POLLS
} from "c/caseAiTriagePanel";
import {
  getRecord,
  updateRecord,
  notifyRecordUpdateAvailable
} from "lightning/uiRecordApi";

jest.mock(
  "lightning/uiRecordApi",
  () => {
    const { createLdsTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return {
      getRecord: createLdsTestWireAdapter(jest.fn()),
      updateRecord: jest.fn(() => Promise.resolve({})),
      notifyRecordUpdateAvailable: jest.fn(() => Promise.resolve())
    };
  },
  { virtual: true }
);

const RECORD_ID = "500000000000001AAA";

function record(values) {
  const fields = {};
  Object.entries(values).forEach(([name, value]) => {
    fields[name] = { value, displayValue: null };
  });
  return { apiName: "Case", id: RECORD_ID, fields };
}

const COMPLETED = {
  Priority: "Medium",
  AI_Status__c: "Completed",
  AI_Category__c: "Billing",
  AI_Suggested_Priority__c: "High",
  AI_Sentiment__c: "Angry",
  AI_Summary__c: "Customer was charged twice.",
  AI_Suggested_Reply__c: "Hi! Sorry about that.",
  AI_Model__c: "anthropic/claude-haiku-5.5",
  AI_Processed_At__c: "2026-11-17T12:00:00.000Z",
  AI_Error__c: null
};

const flush = () => Promise.resolve().then(() => Promise.resolve());
const $ = (el, id) => el.shadowRoot.querySelector(`[data-id="${id}"]`);

function mount() {
  const el = createElement("c-case-ai-triage-panel", { is: CaseAiTriagePanel });
  el.recordId = RECORD_ID;
  document.body.appendChild(el);
  return el;
}

describe("c-case-ai-triage-panel", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
    jest.useRealTimers();
  });

  it("renders the AI analysis of a completed case", async () => {
    const el = mount();
    getRecord.emit(record(COMPLETED));
    await flush();

    expect($(el, "summary").textContent).toBe("Customer was charged twice.");
    expect($(el, "category").label).toBe("Billing");
    expect($(el, "sentiment").label).toBe("Angry");
    expect($(el, "sentiment").iconName).toBe("utility:error");
    expect($(el, "priority").label).toBe("High");
    expect($(el, "reply").textContent).toBe("Hi! Sorry about that.");
    expect($(el, "run").label).toBe("Run again");
  });

  it("offers to apply the suggested priority and updates the case", async () => {
    const el = mount();
    getRecord.emit(record(COMPLETED));
    await flush();

    $(el, "apply-priority").click();
    await flush();

    expect(updateRecord).toHaveBeenCalledWith({
      fields: { Id: RECORD_ID, Priority: "High" }
    });
  });

  it("hides the apply button when priorities already match", async () => {
    const el = mount();
    getRecord.emit(record({ ...COMPLETED, Priority: "High" }));
    await flush();

    expect($(el, "apply-priority")).toBeNull();
  });

  it("re-runs the triage by setting the status back to Pending", async () => {
    const el = mount();
    getRecord.emit(record(COMPLETED));
    await flush();

    $(el, "run").click();
    await flush();

    expect(updateRecord).toHaveBeenCalledWith({
      fields: { Id: RECORD_ID, AI_Status__c: "Pending" }
    });
  });

  it("shows a spinner and polls the record while the triage is pending", async () => {
    jest.useFakeTimers();
    const el = mount();
    getRecord.emit(record({ ...COMPLETED, AI_Status__c: "Pending" }));
    await flush();

    expect($(el, "pending")).not.toBeNull();
    expect($(el, "run").disabled).toBe(true);

    jest.advanceTimersByTime(POLL_INTERVAL_MS);
    await flush();
    expect(notifyRecordUpdateAvailable).toHaveBeenCalledWith([
      { recordId: RECORD_ID }
    ]);

    // The record did not change, so the wire did not re-emit: polling must continue anyway.
    jest.advanceTimersByTime(POLL_INTERVAL_MS);
    await flush();
    expect(notifyRecordUpdateAvailable).toHaveBeenCalledTimes(2);
  });

  it("stops polling once the triage finishes", async () => {
    jest.useFakeTimers();
    const el = mount();
    getRecord.emit(record({ ...COMPLETED, AI_Status__c: "Pending" }));
    await flush();

    getRecord.emit(record(COMPLETED));
    await flush();
    jest.advanceTimersByTime(POLL_INTERVAL_MS * 3);
    await flush();

    expect(notifyRecordUpdateAvailable).not.toHaveBeenCalled();
    expect($(el, "completed")).not.toBeNull();
  });

  it("gives up polling after the maximum number of attempts", async () => {
    jest.useFakeTimers();
    mount();
    getRecord.emit(record({ ...COMPLETED, AI_Status__c: "Pending" }));
    await flush();

    for (let i = 0; i < MAX_POLLS + 5; i++) {
      jest.advanceTimersByTime(POLL_INTERVAL_MS);
      // eslint-disable-next-line no-await-in-loop
      await flush();
    }

    expect(notifyRecordUpdateAvailable).toHaveBeenCalledTimes(MAX_POLLS);
  });

  it("shows the error details when the triage failed", async () => {
    const el = mount();
    getRecord.emit(
      record({
        AI_Status__c: "Failed",
        AI_Error__c: "HTTP 401: Missing Authentication header"
      })
    );
    await flush();

    expect($(el, "failed")).not.toBeNull();
    expect($(el, "error-details").textContent).toContain("HTTP 401");
  });

  it("explains when the case was never triaged", async () => {
    const el = mount();
    getRecord.emit(record({ AI_Status__c: null }));
    await flush();

    expect($(el, "not-triaged")).not.toBeNull();
    expect($(el, "run").label).toBe("Run AI triage");
  });

  it("copies the suggested reply to the clipboard", async () => {
    const writeText = jest.fn(() => Promise.resolve());
    Object.assign(navigator, { clipboard: { writeText } });
    const el = mount();
    getRecord.emit(record(COMPLETED));
    await flush();

    $(el, "copy").click();
    await flush();

    expect(writeText).toHaveBeenCalledWith("Hi! Sorry about that.");
  });

  it("shows an error when the record cannot be loaded", async () => {
    const el = mount();
    getRecord.error({ message: "Insufficient access" });
    await flush();

    expect($(el, "load-error")).not.toBeNull();
  });
});
