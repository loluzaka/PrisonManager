import { createRealtimeClient, type SealedLiveQuery } from "@neon/realtime/client";

type Visit = {
  visit_id: string;
  visit_date: string;
  slot: string;
  status: string;
  inmate_no: string;
  inmate_name: string;
  visitor_name: string;
  block_name: string;
};

type ConnectionOptions = {
  csrf: string;
  onRows: (rows: readonly Visit[]) => void;
  onStatus: (status: string) => void;
  onError: () => void;
};

type SealedResponse = {
  url: string;
  query: SealedLiveQuery<Visit>;
};

async function fetchSealedQuery(csrf: string): Promise<SealedResponse> {
  const response = await fetch("/api/realtime/visits", {
    method: "POST",
    credentials: "same-origin",
    headers: {
      "Content-Type": "application/json",
      "X-CSRF-Token": csrf,
    },
    body: "{}",
  });
  if (!response.ok) {
    throw new Error(`Could not prepare live visits (${response.status})`);
  }
  return (await response.json()) as SealedResponse;
}

export async function connect(options: ConnectionOptions): Promise<() => void> {
  const initial = await fetchSealedQuery(options.csrf);
  const client = createRealtimeClient({ url: initial.url });
  const subscription = client.subscribe(initial.query);
  let stopped = false;
  let timer = 0;

  subscription.onChange((snapshot) => {
    if (snapshot.data) options.onRows(snapshot.data);
  });
  subscription.onStateChange((state) => {
    if (state.status === "error") {
      options.onError();
    } else {
      options.onStatus(state.status);
    }
  });

  const schedule = (delay: number) => {
    window.clearTimeout(timer);
    timer = window.setTimeout(() => void renew(), delay);
  };

  const renew = async () => {
    if (stopped) return;
    let next: SealedResponse;
    try {
      next = await fetchSealedQuery(options.csrf);
    } catch {
      schedule(1000);
      return;
    }
    if (next.url !== initial.url) {
      options.onError();
      return;
    }
    schedule(Math.max(0, next.query.expiresAt - Date.now() - 10_000));
    try {
      await subscription.renew(next.query);
    } catch {
      options.onError();
    }
  };

  schedule(Math.max(0, initial.query.expiresAt - Date.now() - 10_000));
  return () => {
    stopped = true;
    window.clearTimeout(timer);
    subscription.unsubscribe();
    client.close();
  };
}
