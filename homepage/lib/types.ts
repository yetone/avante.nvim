export interface GitHubStats {
  stars: number;
  forks: number;
  watchers: number;
  latest_release: {
    version: string;
    published_at: string;
  };
}

export interface DiscordStats {
  member_count: number;
  online_count: number;
}

export interface Translations {
  nav: {
    home: string;
    features: string;
    installation: string;
    community: string;
    docs: string;
  };
  hero: {
    title: string;
    subtitle: string;
    cta_primary: string;
    cta_secondary: string;
  };
  features: {
    title: string;
    ai_suggestions: {
      title: string;
      description: string;
    };
    one_click: {
      title: string;
      description: string;
    };
    multi_provider: {
      title: string;
      description: string;
    };
    zen_mode: {
      title: string;
      description: string;
    };
    acp: {
      title: string;
      description: string;
    };
    project_instructions: {
      title: string;
      description: string;
    };
    rag_service: {
      title: string;
      description: string;
    };
    custom_tools: {
      title: string;
      description: string;
    };
  };
  installation: {
    title: string;
    subtitle: string;
    lazy_nvim: string;
    packer: string;
    vim_plug: string;
    requirements: string;
    copied: string;
    copy: string;
  };
  community: {
    title: string;
    subtitle: string;
    github: string;
    discord: string;
    stars: string;
    members: string;
  };
  footer: {
    license: string;
    docs: string;
    github: string;
    discord: string;
  };
}
