declare module "cloudflare:test" {
	interface ProvidedEnv extends Env {
		WATCH_PARTY: KVNamespace;
	}
}
