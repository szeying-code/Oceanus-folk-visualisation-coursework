# Task 3 data preparation: Oceanus Folk artist analysis
# Reads data.json (the music knowledge graph provided with the module, included in this repository)
# and writes the files used by the Observable visualisations:
#   timeline.csv, network.json, metrics.csv, potential_stars_all.csv
# Run from the main folder of the repository:  Rscript R/rising_stars_prep.R

# Load libraries
library(jsonlite)
library(dplyr)
library(tidyr)

# Load JSON graph
data <- fromJSON("data.json")
nodes <- data$nodes
edges <- data$links
colnames(nodes) <- tolower(gsub(" ", "_", colnames(nodes)))
colnames(edges) <- tolower(gsub(" ", "_", colnames(edges)))

# Identify Oceanus Folk artists
# Get Oceanus Folk songs
oceanus_songs <- nodes %>%
  filter(node_type == "Song" & genre == "Oceanus Folk")

# Get performers of those songs
oceanus_edges <- edges %>%
  filter(
    edge_type %in% c("PerformerOf", "ComposerOf", "ProducerOf", "LyricistOf"),
    target %in% oceanus_songs$id
  )

# Get unique artists
oceanus_artists <- unique(oceanus_edges$source)

# Get artist nodes
artist_pool <- nodes %>%
  filter(id %in% oceanus_artists)

# Compute metrics for ALL artists
# Join songs with artists
artist_song_data <- oceanus_edges %>%
  left_join(
    nodes %>% select(id, name),
    by = c("source" = "id")
  ) %>%
  left_join(
    nodes %>% select(id, release_date, notable),
    by = c("target" = "id")
  )

# Build scoring table
artist_scores <- artist_song_data %>%
  filter(!is.na(name)) %>%
  group_by(name) %>%
  summarise(
    total_releases = n(),
    notable_releases = sum(notable == TRUE, na.rm = TRUE),
    career_length = max(as.numeric(release_date), na.rm = TRUE) -
      min(as.numeric(release_date), na.rm = TRUE),
    recent_activity = sum(as.numeric(release_date) >= 2035, na.rm = TRUE),
    .groups = "drop"
  )

# Select the best 3 artists
# 1. Superstar (highest notable releases)
top_artist <- artist_scores %>%
  arrange(desc(notable_releases)) %>%
  slice(1)

# 2. Mid-tier (moderate output + consistency)
mid_artist <- artist_scores %>%
  filter(name != top_artist$name) %>%
  arrange(desc(total_releases)) %>%
  slice(2)

# 3. Rising star (high recent activity, lower total history)
rising_artist <- artist_scores %>%
  filter(!name %in% c(top_artist$name, mid_artist$name)) %>%
  arrange(desc(recent_activity)) %>%
  slice(1)
if(nrow(rising_artist) == 0){
  rising_artist <- artist_scores %>%
    arrange(desc(recent_activity)) %>%
    slice(1)
} else {
  rising_artist <- rising_artist %>% slice(1)
}
# Combine
selected_artists <- c(
  top_artist$name,
  mid_artist$name,
  rising_artist$name
)

selected_artists

# Filter nodes for selected artists
artist_nodes <- nodes %>%
  filter(node_type %in% c("Person", "MusicalGroup") &
           name %in% selected_artists)

# Filter edges related to selected artists
relevant_edges <- edges %>%
  filter(source %in% artist_nodes$id | target %in% artist_nodes$id)

# Create timeline of notable songs/albums 
# Merge nodes with relevant edges
artist_song_nodes <- nodes %>%
  filter(node_type %in% c("Song", "Album"))

# Join edges to get which artist performed/composed/produced/Lyriced
artist_song_edges <- relevant_edges %>%
  filter(edge_type %in% c("PerformerOf", "ComposerOf", "ProducerOf", "LyricistOf")) %>%
  left_join(artist_nodes %>% select(id, name), by = c("source" = "id")) %>%
  left_join(artist_song_nodes %>% select(id, release_date, genre,notable), by = c("target" = "id"))

# Timeline data: number of notable songs/albums per year per artist
timeline <- artist_song_edges %>%
  filter(!is.na(name)) %>%
  group_by(name, release_date) %>%
  summarise(
    total_releases = n(),
    notable_releases = sum(notable == TRUE, na.rm = TRUE),
    .groups = "drop"
  )

# Export timeline CSV 
write.csv(timeline, "timeline.csv", row.names = FALSE)

# Create collaboration/influence network 
# Filter edges for collaborations
collab_edges <- relevant_edges %>%
  filter(edge_type %in% c("PerformerOf", "ComposerOf", "ProducerOf", "LyricistOf", "MemberOf"))

# Filter edges for influence
influence_edges <- relevant_edges %>%
  filter(edge_type %in% c("InStyleOf", "InterpolatesFrom", "CoverOf", "LyricalReferenceTo", "DirectlySamples"))

# Get ALL nodes connected to selected artists
connected_ids <- unique(c(
  relevant_edges$source,
  relevant_edges$target
))

all_nodes <- nodes %>%
  filter(id %in% connected_ids)

network_data <- list(
  nodes = all_nodes,   
  edges = bind_rows(collab_edges, influence_edges)
)

# Export network json
write_json(network_data, "network.json", pretty = TRUE)

# Compute basic metrics 
# Metrics: number of collaborations, number of influenced artists, number of genres, output volume
metrics <- artist_nodes %>%
  rowwise() %>%
  mutate(
    collaborations = sum(collab_edges$source == id | collab_edges$target == id),
    influence_count = sum(influence_edges$source == id | influence_edges$target == id),
    genre_diversity = length(unique(na.omit(artist_song_edges$genre[artist_song_edges$name == name]))),
    output_volume = sum(relevant_edges$source == id & relevant_edges$edge_type %in% c("PerformerOf", "ComposerOf", "ProducerOf", "LyricistOf"))
  ) %>%
  select(name, collaborations, influence_count, genre_diversity, output_volume)

# Export metrics CSV
write.csv(metrics, "metrics.csv", row.names = FALSE)

# Compute a potential star score for all Oceanus Folk artists 
potential_stars <- artist_scores %>%
  mutate(
    # Weighted score emphasizing recent activity
    score = recent_activity * 3 + notable_releases * 1.5 + total_releases * 0.5
  ) %>%
  arrange(desc(score))  # ranked from highest potential to lowest

# take top 30 for visualization
top_stars <- potential_stars %>% slice(1:30)

# Export prediction CSV 
write.csv(top_stars, "potential_stars_all.csv", row.names = FALSE)
