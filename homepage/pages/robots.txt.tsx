import { GetServerSideProps } from 'next';

const Robots = () => {
  return null;
};

export const getServerSideProps: GetServerSideProps = async ({ res }) => {
  const robots = `User-agent: *
Allow: /

Sitemap: https://avante.nvim.dev/sitemap.xml`;

  res.setHeader('Content-Type', 'text/plain');
  res.setHeader('Cache-Control', 'public, max-age=86400');
  res.write(robots);
  res.end();

  return {
    props: {},
  };
};

export default Robots;
